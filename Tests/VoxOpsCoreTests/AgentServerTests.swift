// Tests/VoxOpsCoreTests/AgentServerTests.swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("AgentServer and AgentProfile")
struct AgentServerTests {
    @Test("AgentServer JSON round-trip")
    func agentServerRoundTrip() throws {
        let serverId = UUID()
        let server = AgentServer(id: serverId, name: "My Server", type: .openclaw, url: "http://localhost:8080", enabled: true)
        let data = try JSONEncoder().encode(server)
        let decoded = try JSONDecoder().decode(AgentServer.self, from: data)
        #expect(decoded.id == serverId)
        #expect(decoded.name == "My Server")
        #expect(decoded.type == .openclaw)
        #expect(decoded.url == "http://localhost:8080")
        #expect(decoded.enabled == true)
    }

    @Test("AgentProfile round-trip with composite id")
    func agentProfileRoundTripAndCompositeId() throws {
        let serverId = UUID()
        let profile = AgentProfile(id: "my-agent", serverId: serverId, name: "My Agent", enabled: true)

        // Verify composite id
        #expect(profile.id == "\(serverId):my-agent")
        #expect(profile.agentId == "my-agent")

        // JSON round-trip
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(AgentProfile.self, from: data)
        #expect(decoded.agentId == "my-agent")
        #expect(decoded.serverId == serverId)
        #expect(decoded.name == "My Agent")
        #expect(decoded.enabled == true)
        #expect(decoded.id == "\(serverId):my-agent")
    }

    @Test("AgentServer array round-trip")
    func agentServerArrayRoundTrip() throws {
        let servers = [
            AgentServer(name: "Server A", type: .openclaw, url: "http://localhost:8080"),
            AgentServer(name: "Server B", type: .hermes, url: "http://localhost:9090", enabled: false),
        ]
        let data = try JSONEncoder().encode(servers)
        let decoded = try JSONDecoder().decode([AgentServer].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].name == "Server A")
        #expect(decoded[0].type == .openclaw)
        #expect(decoded[1].name == "Server B")
        #expect(decoded[1].type == .hermes)
        #expect(decoded[1].enabled == false)
    }
}
