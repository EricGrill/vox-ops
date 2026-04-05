import Foundation

public struct AgentServer: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var type: ServerType
    public var url: String
    public var enabled: Bool
    public init(id: UUID = UUID(), name: String, type: ServerType, url: String, enabled: Bool = true) {
        self.id = id; self.name = name; self.type = type; self.url = url; self.enabled = enabled
    }
}
