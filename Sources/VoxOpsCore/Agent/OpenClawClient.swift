// Sources/VoxOpsCore/Agent/OpenClawClient.swift
import Foundation

// MARK: - Supporting Types

public struct OpenClawResponse: Sendable {
    public let id: String
    public let ok: Bool
    public let payload: [String: Any]?
    public let errorMessage: String?
}

public struct AgentListEntry: Sendable {
    public let id: String
    public let name: String
}

public enum OpenClawError: Error, Sendable {
    case invalidFrame(String)
    case connectionFailed(String)
    case authFailed(String)
    case notConnected
}

// MARK: - OpenClawFrames

public enum OpenClawFrames {

    // MARK: Frame Builders

    public static func connect(id: String, token: String) -> Data {
        let frame: [String: Any] = [
            "type": "req",
            "method": "connect",
            "id": id,
            "params": ["token": token],
        ]
        return try! JSONSerialization.data(withJSONObject: frame)
    }

    public static func agentsList(id: String) -> Data {
        let frame: [String: Any] = [
            "type": "req",
            "method": "agents.list",
            "id": id,
        ]
        return try! JSONSerialization.data(withJSONObject: frame)
    }

    public static func agent(
        id: String,
        messages: [ChatMessage],
        agentId: String,
        idempotencyKey: String
    ) -> Data {
        let encodedMessages = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        let frame: [String: Any] = [
            "type": "req",
            "method": "agent",
            "id": id,
            "params": [
                "agentId": agentId,
                "idempotencyKey": idempotencyKey,
                "messages": encodedMessages,
            ] as [String: Any],
        ]
        return try! JSONSerialization.data(withJSONObject: frame)
    }

    // MARK: Frame Parsers

    /// Returns `(runId, event)`. Event is nil for "done" signals.
    public static func parseEvent(from data: Data) throws -> (runId: String?, event: AgentEvent?) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenClawError.invalidFrame("Not a JSON object")
        }
        let runId = json["runId"] as? String
        guard let eventDict = json["event"] as? [String: Any],
              let kind = eventDict["kind"] as? String
        else {
            throw OpenClawError.invalidFrame("Missing event.kind")
        }
        switch kind {
        case "textChunk":
            let text = eventDict["text"] as? String ?? ""
            return (runId, .textChunk(text))
        case "error":
            let message = eventDict["message"] as? String ?? "Unknown error"
            return (runId, .error(message))
        case "done":
            return (runId, nil)
        default:
            throw OpenClawError.invalidFrame("Unknown event kind: \(kind)")
        }
    }

    public static func parseResponse(from data: Data) throws -> OpenClawResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenClawError.invalidFrame("Not a JSON object")
        }
        guard let id = json["id"] as? String else {
            throw OpenClawError.invalidFrame("Missing response id")
        }
        let ok = json["ok"] as? Bool ?? false
        let payload = json["payload"] as? [String: Any]
        let errorMessage = json["error"] as? String
        return OpenClawResponse(id: id, ok: ok, payload: payload, errorMessage: errorMessage)
    }

    public static func parseAgentsList(from response: OpenClawResponse) throws -> [AgentListEntry] {
        guard let payload = response.payload,
              let agents = payload["agents"] as? [[String: Any]]
        else {
            throw OpenClawError.invalidFrame("Missing agents array in payload")
        }
        return agents.compactMap { dict -> AgentListEntry? in
            guard let id = dict["id"] as? String,
                  let name = dict["name"] as? String
            else { return nil }
            return AgentListEntry(id: id, name: name)
        }
    }
}

// MARK: - OpenClawClient

@available(macOS 14, *)
public final class OpenClawClient: AgentClient, @unchecked Sendable {

    public let serverId: UUID
    public let serverType: ServerType = .openclaw

    private let url: URL
    private let token: String
    private let lock = NSLock()

    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false

    /// Maps requestId → runId (populated when response arrives with runId)
    private var requestToRunId: [String: String] = [:]
    /// Maps runId → stream continuation
    private var runStreams: [String: AsyncThrowingStream<AgentEvent, Error>.Continuation] = [:]
    /// Maps requestId → stream continuation (pending until runId arrives)
    private var pendingStreams: [String: AsyncThrowingStream<AgentEvent, Error>.Continuation] = [:]

    private var receiveTask: Task<Void, Never>?

    // Auto-reconnect state
    private var reconnectAttempts = 0
    private static let maxReconnectAttempts = 5
    private static let baseBackoffSeconds: Double = 1.0

    public init(serverId: UUID, url: URL, token: String) {
        self.serverId = serverId
        self.url = url
        self.token = token
    }

    // MARK: - AgentClient Conformance

    public func connect() async throws {
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        task.resume()

        lock.lock()
        self.session = session
        self.webSocketTask = task
        lock.unlock()

        // Send connect frame
        let reqId = UUID().uuidString
        let frame = OpenClawFrames.connect(id: reqId, token: token)
        try await sendRaw(frame)

        // Wait for response
        let responseData = try await receiveRaw()
        let response = try OpenClawFrames.parseResponse(from: responseData)
        guard response.ok else {
            throw OpenClawError.authFailed(response.errorMessage ?? "Auth failed")
        }

        lock.lock()
        isConnected = true
        reconnectAttempts = 0
        lock.unlock()

        // Start background receive loop
        startReceiveLoop()
    }

    public func disconnect() async {
        lock.lock()
        let task = webSocketTask
        isConnected = false
        lock.unlock()

        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .normalClosure, reason: nil)

        lock.lock()
        webSocketTask = nil
        // Finish all pending streams with cancellation
        for continuation in pendingStreams.values { continuation.finish(throwing: CancellationError()) }
        for continuation in runStreams.values { continuation.finish(throwing: CancellationError()) }
        pendingStreams.removeAll()
        runStreams.removeAll()
        requestToRunId.removeAll()
        lock.unlock()
    }

    public func listAgents() async throws -> [AgentProfile] {
        try await ensureConnected()

        let reqId = UUID().uuidString
        let frame = OpenClawFrames.agentsList(id: reqId)
        try await sendRaw(frame)

        let responseData = try await receiveRaw()
        let response = try OpenClawFrames.parseResponse(from: responseData)
        guard response.ok else {
            throw OpenClawError.connectionFailed(response.errorMessage ?? "Failed to list agents")
        }

        let entries = try OpenClawFrames.parseAgentsList(from: response)
        return entries.map { entry in
            AgentProfile(id: entry.id, serverId: serverId, name: entry.name)
        }
    }

    public func send(messages: [ChatMessage], agentId: String) -> AsyncThrowingStream<AgentEvent, Error> {
        let reqId = UUID().uuidString
        let idempotencyKey = UUID().uuidString

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await ensureConnected()

                    lock.lock()
                    pendingStreams[reqId] = continuation
                    lock.unlock()

                    let frame = OpenClawFrames.agent(
                        id: reqId,
                        messages: messages,
                        agentId: agentId,
                        idempotencyKey: idempotencyKey
                    )
                    try await sendRaw(frame)

                    // Wait for the response that maps reqId → runId
                    let responseData = try await receiveRaw()
                    let response = try OpenClawFrames.parseResponse(from: responseData)

                    guard response.ok else {
                        lock.lock()
                        pendingStreams.removeValue(forKey: reqId)
                        lock.unlock()
                        continuation.finish(throwing: OpenClawError.connectionFailed(
                            response.errorMessage ?? "Agent request failed"
                        ))
                        return
                    }

                    // The response payload may include a runId; if so, migrate the pending stream
                    if let payload = response.payload, let runId = payload["runId"] as? String {
                        lock.lock()
                        pendingStreams.removeValue(forKey: reqId)
                        requestToRunId[reqId] = runId
                        runStreams[runId] = continuation
                        lock.unlock()
                    }
                    // If no runId in response, leave stream pending; the receive loop will route by runId from events
                } catch {
                    lock.lock()
                    pendingStreams.removeValue(forKey: reqId)
                    lock.unlock()
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func healthCheck() async -> Bool {
        lock.lock()
        let connected = isConnected
        lock.unlock()
        return connected
    }

    // MARK: - Private Helpers

    private func ensureConnected() async throws {
        lock.lock()
        let connected = isConnected
        lock.unlock()
        guard connected else {
            throw OpenClawError.notConnected
        }
    }

    private func sendRaw(_ data: Data) async throws {
        lock.lock()
        let task = webSocketTask
        lock.unlock()
        guard let task else { throw OpenClawError.notConnected }
        let message = URLSessionWebSocketTask.Message.data(data)
        try await task.send(message)
    }

    private func receiveRaw() async throws -> Data {
        lock.lock()
        let task = webSocketTask
        lock.unlock()
        guard let task else { throw OpenClawError.notConnected }
        let message = try await task.receive()
        switch message {
        case .data(let data): return data
        case .string(let str):
            guard let data = str.data(using: .utf8) else {
                throw OpenClawError.invalidFrame("Could not decode string message")
            }
            return data
        @unknown default:
            throw OpenClawError.invalidFrame("Unknown message type")
        }
    }

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let data = try await self.receiveRaw()
                    await self.handleIncoming(data: data)
                } catch {
                    if Task.isCancelled { break }
                    // Check if reconnect is warranted
                    await self.handleDisconnect(error: error)
                    break
                }
            }
        }
    }

    private func handleIncoming(data: Data) async {
        // Try parsing as event first
        if let result = try? OpenClawFrames.parseEvent(from: data) {
            guard let runId = result.runId else { return }
            lock.lock()
            let continuation = runStreams[runId]
            lock.unlock()
            if let continuation {
                if let event = result.event {
                    continuation.yield(event)
                } else {
                    continuation.finish()
                    lock.lock()
                    runStreams.removeValue(forKey: runId)
                    lock.unlock()
                }
            }
            return
        }

        // Otherwise try as response (e.g. for agent req that returns runId)
        if let response = try? OpenClawFrames.parseResponse(from: data) {
            if let payload = response.payload, let runId = payload["runId"] as? String {
                lock.lock()
                let pending = pendingStreams.removeValue(forKey: response.id)
                if let pending {
                    requestToRunId[response.id] = runId
                    runStreams[runId] = pending
                }
                lock.unlock()
            }
        }
    }

    private func handleDisconnect(error: Error) async {
        lock.lock()
        isConnected = false
        let attempts = reconnectAttempts
        lock.unlock()

        guard attempts < Self.maxReconnectAttempts else {
            // Exhaust all streams
            lock.lock()
            for c in pendingStreams.values { c.finish(throwing: error) }
            for c in runStreams.values { c.finish(throwing: error) }
            pendingStreams.removeAll()
            runStreams.removeAll()
            lock.unlock()
            return
        }

        let delay = Self.baseBackoffSeconds * pow(2.0, Double(attempts))
        let clampedDelay = min(delay, 8.0)
        lock.lock()
        reconnectAttempts += 1
        lock.unlock()

        try? await Task.sleep(nanoseconds: UInt64(clampedDelay * 1_000_000_000))

        do {
            try await connect()
        } catch {
            await handleDisconnect(error: error)
        }
    }
}
