import Foundation

public struct ChatMessage: Codable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant, system }
    public let role: Role
    public let content: String
    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public enum ServerType: String, Codable, Sendable {
    case openclaw
    case hermes
}

public enum AgentEvent: Sendable, Equatable {
    case textChunk(String)
    case error(String)
}

public protocol AgentClient: Sendable {
    var serverId: UUID { get }
    var serverType: ServerType { get }
    func connect() async throws
    func disconnect() async
    func listAgents() async throws -> [AgentProfile]
    func send(messages: [ChatMessage], agentId: String) -> AsyncThrowingStream<AgentEvent, Error>
    func healthCheck() async -> Bool
}
