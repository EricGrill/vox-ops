import Foundation

/// Manages all agent client connections. Runs on @MainActor to avoid
/// hop overhead with ChatViewModel and AppState (both @MainActor).
@MainActor
public final class AgentClientManager {
    private var clients: [UUID: any AgentClient] = [:]

    public init() {}

    public func register(client: any AgentClient) {
        clients[client.serverId] = client
    }

    public func client(for serverId: UUID) -> (any AgentClient)? {
        clients[serverId]
    }

    public func removeClient(for serverId: UUID) async {
        if let client = clients.removeValue(forKey: serverId) {
            await client.disconnect()
        }
    }

    public func allAgents() async throws -> [AgentProfile] {
        var all: [AgentProfile] = []
        for (_, client) in clients {
            let agents = try await client.listAgents()
            all.append(contentsOf: agents)
        }
        return all
    }

    public func allEnabledAgents() async throws -> [AgentProfile] {
        try await allAgents().filter(\.enabled)
    }

    public func connectAll() async {
        for (_, client) in clients {
            try? await client.connect()
        }
    }

    public func disconnectAll() async {
        for (_, client) in clients {
            await client.disconnect()
        }
        clients.removeAll()
    }

    public func clientForAgent(_ agentId: String, serverId: UUID) -> (any AgentClient)? {
        clients[serverId]
    }
}
