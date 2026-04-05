import Foundation

public struct AgentProfile: Codable, Identifiable, Sendable, Equatable {
    /// Composite ID unique across servers: "serverId:agentId"
    public var id: String { "\(serverId):\(agentId)" }
    public let agentId: String
    public let serverId: UUID
    public var name: String
    public var enabled: Bool
    public init(id: String, serverId: UUID, name: String, enabled: Bool = true) {
        self.agentId = id; self.serverId = serverId; self.name = name; self.enabled = enabled
    }
    enum CodingKeys: String, CodingKey {
        case agentId = "id"
        case serverId, name, enabled
    }
}
