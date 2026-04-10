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

public enum OpenClawError: Error, Sendable, LocalizedError {
    case invalidFrame(String)
    case connectionFailed(String)
    case authFailed(String)
    case notConnected
    case timeout

    public var errorDescription: String? {
        switch self {
        case .invalidFrame(let msg): return "Invalid frame: \(msg)"
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .authFailed(let msg): return "Auth failed: \(msg)"
        case .notConnected: return "Not connected"
        case .timeout: return "Request timed out"
        }
    }
}

// MARK: - OpenClawFrames

public enum OpenClawFrames {

    // MARK: Frame Builders

    public static func connect(id: String, token: String) -> Data {
        var params: [String: Any] = [
            "minProtocol": 3,
            "maxProtocol": 3,
            "client": [
                "id": "openclaw-control-ui",
                "version": "1.0.0",
                "platform": "macos",
                "mode": "ui",
                "displayName": "VoxOps",
            ] as [String: Any],
            "role": "operator",
            "scopes": ["operator.read", "operator.write"],
        ]
        if !token.isEmpty {
            params["auth"] = ["token": token]
        }
        let frame: [String: Any] = [
            "type": "req",
            "method": "connect",
            "id": id,
            "params": params,
        ]
        return (try? JSONSerialization.data(withJSONObject: frame)) ?? Data()
    }

    public static func agentsList(id: String) -> Data {
        let frame: [String: Any] = [
            "type": "req",
            "method": "agents.list",
            "id": id,
            "params": [:] as [String: Any],
        ]
        return (try? JSONSerialization.data(withJSONObject: frame)) ?? Data()
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
        return (try? JSONSerialization.data(withJSONObject: frame)) ?? Data()
    }

    // MARK: Frame Parsers

    /// Parse any incoming JSON frame into its type
    public static func parseFrame(from data: Data) throws -> (type: String, json: [String: Any]) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenClawError.invalidFrame("Not a JSON object")
        }
        guard let type = json["type"] as? String else {
            throw OpenClawError.invalidFrame("Missing 'type' field")
        }
        return (type, json)
    }

    public static func parseResponse(from data: Data) throws -> OpenClawResponse {
        let (type, json) = try parseFrame(from: data)
        guard type == "res" else {
            throw OpenClawError.invalidFrame("Expected 'res', got '\(type)'")
        }
        guard let id = json["id"] as? String else {
            throw OpenClawError.invalidFrame("Missing response id")
        }
        let ok = json["ok"] as? Bool ?? false
        let payload = json["payload"] as? [String: Any]
        // Error can be a string or an object with "message" field
        let errorMessage: String?
        if let errObj = json["error"] as? [String: Any] {
            errorMessage = errObj["message"] as? String
        } else {
            errorMessage = json["error"] as? String
        }
        return OpenClawResponse(id: id, ok: ok, payload: payload, errorMessage: errorMessage)
    }

    /// Returns `(runId, event)`. Event is nil for "done" signals.
    public static func parseStreamEvent(from json: [String: Any]) throws -> (runId: String?, event: AgentEvent?) {
        let runId = json["runId"] as? String
        guard let payload = json["payload"] as? [String: Any],
              let kind = payload["kind"] as? String
        else {
            throw OpenClawError.invalidFrame("Missing payload.kind in event")
        }
        switch kind {
        case "textChunk":
            let text = payload["text"] as? String ?? ""
            return (runId, .textChunk(text))
        case "error":
            let message = payload["message"] as? String ?? "Unknown error"
            return (runId, .error(message))
        case "done":
            return (runId, nil)
        default:
            throw OpenClawError.invalidFrame("Unknown event kind: \(kind)")
        }
    }

    public static func parseAgentsList(from response: OpenClawResponse) throws -> [AgentListEntry] {
        guard let payload = response.payload,
              let agents = payload["agents"] as? [[String: Any]]
        else {
            throw OpenClawError.invalidFrame("Missing agents array in payload")
        }
        return agents.compactMap { dict -> AgentListEntry? in
            guard let id = dict["id"] as? String else { return nil }
            // Name can be at top level or inside identity object
            let name: String
            if let n = dict["name"] as? String {
                name = n
            } else if let identity = dict["identity"] as? [String: Any],
                      let n = identity["name"] as? String {
                name = n
            } else {
                name = id
            }
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
    /// Maps requestId → response continuation (for request/response calls like listAgents)
    private var responseHandlers: [String: CheckedContinuation<OpenClawResponse, Error>] = [:]

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

        // Build request with Origin header for control-ui auth
        var request = URLRequest(url: url)
        // Derive Origin from the gateway URL (http scheme, same host:port)
        if var originComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            originComponents.scheme = "http"
            originComponents.path = ""
            if let origin = originComponents.url?.absoluteString {
                request.addValue(origin, forHTTPHeaderField: "Origin")
            }
        }

        let task = session.webSocketTask(with: request)
        task.resume()

        lock.lock()
        self.session = session
        self.webSocketTask = task
        lock.unlock()

        // Server sends a connect.challenge event first — read and discard it
        let challengeData = try await receiveRaw()
        if let challengeStr = String(data: challengeData, encoding: .utf8) {
            NSLog("[VoxOps] connect challenge: %@", String(challengeStr.prefix(500)))
        }

        // Send connect frame with proper protocol v3 params
        let reqId = UUID().uuidString
        let frame = OpenClawFrames.connect(id: reqId, token: token)
        try await sendRaw(frame)

        // Wait for response — could be "res" type (ok/error)
        let responseData = try await receiveRaw()
        if let respStr = String(data: responseData, encoding: .utf8) {
            NSLog("[VoxOps] connect response: %@", String(respStr.prefix(500)))
        }

        let response = try OpenClawFrames.parseResponse(from: responseData)
        guard response.ok else {
            NSLog("[VoxOps] OpenClaw auth failed: %@", response.errorMessage ?? "unknown")
            throw OpenClawError.authFailed(response.errorMessage ?? "Auth failed")
        }

        lock.lock()
        isConnected = true
        reconnectAttempts = 0
        lock.unlock()

        NSLog("[VoxOps] OpenClaw connected successfully to %@", url.absoluteString)
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
        for continuation in pendingStreams.values { continuation.finish(throwing: CancellationError()) }
        for continuation in runStreams.values { continuation.finish(throwing: CancellationError()) }
        for handler in responseHandlers.values { handler.resume(throwing: CancellationError()) }
        pendingStreams.removeAll()
        runStreams.removeAll()
        requestToRunId.removeAll()
        responseHandlers.removeAll()
        lock.unlock()
    }

    public func listAgents() async throws -> [AgentProfile] {
        try await ensureConnected()

        let reqId = UUID().uuidString
        let frame = OpenClawFrames.agentsList(id: reqId)

        // Use a timeout so we don't hang forever
        let response: OpenClawResponse = try await withThrowingTaskGroup(of: OpenClawResponse.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.lock.lock()
                    self.responseHandlers[reqId] = continuation
                    self.lock.unlock()
                    Task {
                        do {
                            try await self.sendRaw(frame)
                        } catch {
                            self.lock.lock()
                            let handler = self.responseHandlers.removeValue(forKey: reqId)
                            self.lock.unlock()
                            handler?.resume(throwing: error)
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10s timeout
                self.lock.lock()
                let handler = self.responseHandlers.removeValue(forKey: reqId)
                self.lock.unlock()
                handler?.resume(throwing: OpenClawError.timeout)
                throw OpenClawError.timeout
            }

            guard let result = try await group.next() else {
                throw OpenClawError.timeout
            }
            group.cancelAll()
            return result
        }

        NSLog("[VoxOps] listAgents response ok=%d payload=%@", response.ok ? 1 : 0, String(describing: response.payload))
        guard response.ok else {
            throw OpenClawError.connectionFailed(response.errorMessage ?? "Failed to list agents")
        }

        let entries = try OpenClawFrames.parseAgentsList(from: response)
        NSLog("[VoxOps] parsed %d agents", entries.count)
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

                    let response: OpenClawResponse = try await withThrowingTaskGroup(of: OpenClawResponse.self) { group in
                        group.addTask {
                            try await withCheckedThrowingContinuation { respContinuation in
                                self.lock.lock()
                                self.responseHandlers[reqId] = respContinuation
                                self.lock.unlock()
                                Task {
                                    do {
                                        let frame = OpenClawFrames.agent(
                                            id: reqId,
                                            messages: messages,
                                            agentId: agentId,
                                            idempotencyKey: idempotencyKey
                                        )
                                        try await self.sendRaw(frame)
                                    } catch {
                                        self.lock.lock()
                                        let handler = self.responseHandlers.removeValue(forKey: reqId)
                                        self.lock.unlock()
                                        handler?.resume(throwing: error)
                                    }
                                }
                            }
                        }
                        group.addTask {
                            try await Task.sleep(nanoseconds: 30_000_000_000)
                            self.lock.lock()
                            let handler = self.responseHandlers.removeValue(forKey: reqId)
                            self.lock.unlock()
                            handler?.resume(throwing: OpenClawError.timeout)
                            throw OpenClawError.timeout
                        }
                        let result = try await group.next()!
                        group.cancelAll()
                        return result
                    }

                    guard response.ok else {
                        continuation.finish(throwing: OpenClawError.connectionFailed(
                            response.errorMessage ?? "Agent request failed"
                        ))
                        return
                    }

                    if let payload = response.payload, let runId = payload["runId"] as? String {
                        lock.lock()
                        requestToRunId[reqId] = runId
                        runStreams[runId] = continuation
                        lock.unlock()
                    } else {
                        lock.lock()
                        pendingStreams[reqId] = continuation
                        lock.unlock()
                    }
                } catch {
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
        if !connected {
            try await connect()
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
                    await self.handleDisconnect(error: error)
                    break
                }
            }
        }
    }

    private func handleIncoming(data: Data) async {
        let raw = String(data: data, encoding: .utf8) ?? "<binary>"
        NSLog("[VoxOps] incoming: %@", String(raw.prefix(1000)))

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else {
            NSLog("[VoxOps] unhandled frame (no type): %@", String(raw.prefix(500)))
            return
        }

        // Handle response frames (listAgents, agent acks, etc.)
        if type == "res" {
            if let response = try? OpenClawFrames.parseResponse(from: data) {
                lock.lock()
                let handler = responseHandlers.removeValue(forKey: response.id)
                lock.unlock()
                if let handler {
                    handler.resume(returning: response)
                    return
                }

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
            return
        }

        // Handle event frames (streaming agent events, server pushes)
        if type == "event" {
            let eventName = json["event"] as? String ?? ""
            // Agent streaming events have payload.kind
            if let result = try? OpenClawFrames.parseStreamEvent(from: json) {
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
            // Other server events (presence, health, etc.) — ignore for now
            NSLog("[VoxOps] ignoring event: %@", eventName)
            return
        }

        NSLog("[VoxOps] unhandled frame type '%@': %@", type, String(raw.prefix(500)))
    }

    private func handleDisconnect(error: Error) async {
        lock.lock()
        isConnected = false
        lock.unlock()

        NSLog("[VoxOps] disconnected: %@", error.localizedDescription)

        // Reconnect loop (non-recursive to avoid stack overflow)
        while !Task.isCancelled {
            lock.lock()
            let attempts = reconnectAttempts
            lock.unlock()

            guard attempts < Self.maxReconnectAttempts else {
                NSLog("[VoxOps] max reconnect attempts reached, giving up")
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

            NSLog("[VoxOps] reconnect attempt %d in %.1fs", attempts + 1, clampedDelay)
            try? await Task.sleep(nanoseconds: UInt64(clampedDelay * 1_000_000_000))

            do {
                try await connect()
                return // success
            } catch {
                NSLog("[VoxOps] reconnect failed: %@", error.localizedDescription)
                continue
            }
        }
    }
}
