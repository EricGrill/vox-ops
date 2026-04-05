// Tests/VoxOpsCoreTests/AgentClientManagerTests.swift
import Testing
import Foundation
@testable import VoxOpsCore

// MARK: - Mock

final class MockAgentClient: AgentClient, @unchecked Sendable {
    let serverId: UUID
    let serverType: ServerType
    var connectCalled = false
    var disconnectCalled = false
    var mockAgents: [AgentProfile]

    init(serverId: UUID = UUID(), serverType: ServerType = .openclaw, mockAgents: [AgentProfile] = []) {
        self.serverId = serverId
        self.serverType = serverType
        self.mockAgents = mockAgents
    }

    func connect() async throws { connectCalled = true }
    func disconnect() async { disconnectCalled = true }
    func listAgents() async throws -> [AgentProfile] { mockAgents }
    func send(messages: [ChatMessage], agentId: String) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { _ in }
    }
    func healthCheck() async -> Bool { true }
}

// MARK: - Tests

@Suite("AgentClientManager")
struct AgentClientManagerTests {

    @Test("registers and retrieves client by serverId")
    @MainActor func registerAndRetrieve() async {
        let manager = AgentClientManager()
        let client = MockAgentClient()

        manager.register(client: client)

        let retrieved = manager.client(for: client.serverId)
        #expect(retrieved != nil)
        #expect(retrieved?.serverId == client.serverId)
    }

    @Test("allAgents aggregates from all clients")
    @MainActor func allAgents() async throws {
        let manager = AgentClientManager()
        let id1 = UUID()
        let id2 = UUID()
        let agent1 = AgentProfile(id: "agent-a", serverId: id1, name: "Agent A")
        let agent2 = AgentProfile(id: "agent-b", serverId: id2, name: "Agent B")

        let client1 = MockAgentClient(serverId: id1, mockAgents: [agent1])
        let client2 = MockAgentClient(serverId: id2, mockAgents: [agent2])

        manager.register(client: client1)
        manager.register(client: client2)

        let agents = try await manager.allAgents()
        #expect(agents.count == 2)
        #expect(agents.contains(agent1))
        #expect(agents.contains(agent2))
    }

    @Test("removeClient disconnects and removes")
    @MainActor func removeClient() async {
        let manager = AgentClientManager()
        let client = MockAgentClient()

        manager.register(client: client)
        #expect(manager.client(for: client.serverId) != nil)

        await manager.removeClient(for: client.serverId)

        #expect(client.disconnectCalled)
        #expect(manager.client(for: client.serverId) == nil)
    }
}
