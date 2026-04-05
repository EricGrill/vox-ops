import Foundation

// MARK: - HermesRequestBuilder

public enum HermesRequestBuilder {
    /// Builds the JSON body for a `/v1/chat/completions` request.
    public static func chatCompletions(messages: [ChatMessage], stream: Bool) throws -> Data {
        let body: [String: Any] = [
            "model": "hermes-agent",
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "stream": stream,
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }
}

// MARK: - HermesSSEParser

public enum HermesSSEParser {
    private static let dataPrefix = "data: "

    /// Parses a single SSE line and returns an `AgentEvent` if the line carries text content.
    public static func parseLine(_ line: String) -> AgentEvent? {
        guard line.hasPrefix(dataPrefix) else { return nil }
        let payload = String(line.dropFirst(dataPrefix.count))
        guard payload != "[DONE]" else { return nil }

        guard
            let data = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let firstChoice = choices.first,
            let delta = firstChoice["delta"] as? [String: Any]
        else { return nil }

        // Only yield an event when the `content` key is present (even if empty).
        guard let content = delta["content"] as? String else { return nil }
        return .textChunk(content)
    }
}

// MARK: - HermesError

public enum HermesError: Error, Sendable {
    case invalidURL
    case httpError(statusCode: Int, body: String)
    case noResponse
}

// MARK: - HermesClient

public final class HermesClient: AgentClient, @unchecked Sendable {
    public let serverId: UUID
    public let serverType: ServerType = .hermes

    private let baseURL: URL
    private let token: String?
    private let session: URLSession

    public init(server: AgentServer, token: String? = nil, session: URLSession = .shared) throws {
        guard let url = URL(string: server.url) else { throw HermesError.invalidURL }
        self.serverId = server.id
        self.baseURL = url
        self.token = token
        self.session = session
    }

    // MARK: AgentClient

    public func connect() async throws {
        let reachable = await healthCheck()
        guard reachable else { throw HermesError.noResponse }
    }

    public func disconnect() async {
        // HTTP is stateless — nothing to tear down.
    }

    public func listAgents() async throws -> [AgentProfile] {
        [AgentProfile(id: "hermes-agent", serverId: serverId, name: "Hermes Agent")]
    }

    public func send(messages: [ChatMessage], agentId: String) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = baseURL.appendingPathComponent("v1/chat/completions")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let token {
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }
                    request.httpBody = try HermesRequestBuilder.chatCompletions(messages: messages, stream: true)

                    let (asyncBytes, response) = try await session.bytes(for: request)

                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var body = ""
                        for try await byte in asyncBytes {
                            body.append(Character(UnicodeScalar(byte)))
                        }
                        throw HermesError.httpError(statusCode: http.statusCode, body: body)
                    }

                    for try await line in asyncBytes.lines {
                        if Task.isCancelled { break }
                        if let event = HermesSSEParser.parseLine(line) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func healthCheck() async -> Bool {
        let url = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}
