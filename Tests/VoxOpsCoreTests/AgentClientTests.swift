// Tests/VoxOpsCoreTests/AgentClientTests.swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("AgentClient Types")
struct AgentClientTests {
    @Test("ChatMessage JSON round-trip")
    func chatMessageRoundTrip() throws {
        let message = ChatMessage(role: .user, content: "Hello, agent!")
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        #expect(decoded.role == .user)
        #expect(decoded.content == "Hello, agent!")
    }

    @Test("ChatMessage role encoding")
    func chatMessageRoleEncoding() throws {
        let user = ChatMessage(role: .user, content: "user msg")
        let assistant = ChatMessage(role: .assistant, content: "assistant msg")
        let system = ChatMessage(role: .system, content: "system msg")

        let userData = try JSONEncoder().encode(user)
        let assistantData = try JSONEncoder().encode(assistant)
        let systemData = try JSONEncoder().encode(system)

        let userJSON = String(data: userData, encoding: .utf8)!
        let assistantJSON = String(data: assistantData, encoding: .utf8)!
        let systemJSON = String(data: systemData, encoding: .utf8)!

        #expect(userJSON.contains("\"user\""))
        #expect(assistantJSON.contains("\"assistant\""))
        #expect(systemJSON.contains("\"system\""))
    }

    @Test("ServerType round-trip")
    func serverTypeRoundTrip() throws {
        let openclaw = ServerType.openclaw
        let hermes = ServerType.hermes

        let openclawData = try JSONEncoder().encode(openclaw)
        let hermesData = try JSONEncoder().encode(hermes)

        let decodedOpenclaw = try JSONDecoder().decode(ServerType.self, from: openclawData)
        let decodedHermes = try JSONDecoder().decode(ServerType.self, from: hermesData)

        #expect(decodedOpenclaw == .openclaw)
        #expect(decodedHermes == .hermes)

        let openclawJSON = String(data: openclawData, encoding: .utf8)!
        let hermesJSON = String(data: hermesData, encoding: .utf8)!
        #expect(openclawJSON.contains("\"openclaw\""))
        #expect(hermesJSON.contains("\"hermes\""))
    }
}
