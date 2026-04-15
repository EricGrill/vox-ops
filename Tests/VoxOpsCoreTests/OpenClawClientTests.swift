// Tests/VoxOpsCoreTests/OpenClawClientTests.swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("OpenClawClient Frame Protocol")
struct OpenClawClientTests {

    // MARK: - Frame Building

    @Test("builds connect frame with token")
    func buildsConnectFrame() throws {
        let id = "req-1"
        let token = "my-secret-token"
        let data = OpenClawFrames.connect(id: id, token: token)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "req")
        #expect(json["method"] as? String == "connect")
        #expect(json["id"] as? String == id)
        let params = json["params"] as? [String: Any]
        let auth = params?["auth"] as? [String: Any]
        #expect(auth?["token"] as? String == token)
    }

    @Test("builds agents.list frame")
    func buildsAgentsListFrame() throws {
        let id = "req-2"
        let data = OpenClawFrames.agentsList(id: id)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "req")
        #expect(json["method"] as? String == "agents.list")
        #expect(json["id"] as? String == id)
    }

    @Test("builds agent message frame")
    func buildsAgentMessageFrame() throws {
        let id = "req-3"
        let agentId = "agent-abc"
        let idempotencyKey = "idem-xyz"
        let messages = [
            ChatMessage(role: .user, content: "Hello!"),
            ChatMessage(role: .assistant, content: "Hi there!"),
        ]

        let data = OpenClawFrames.agent(id: id, messages: messages, agentId: agentId, idempotencyKey: idempotencyKey)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "req")
        #expect(json["method"] as? String == "agent")
        #expect(json["id"] as? String == id)

        let params = json["params"] as? [String: Any]
        #expect(params?["agentId"] as? String == agentId)
        #expect(params?["idempotencyKey"] as? String == idempotencyKey)

        let msgs = params?["messages"] as? [[String: Any]]
        #expect(msgs?.count == 2)
        #expect(msgs?[0]["role"] as? String == "user")
        #expect(msgs?[0]["content"] as? String == "Hello!")
        #expect(msgs?[1]["role"] as? String == "assistant")
    }

    // MARK: - Event Parsing

    @Test("parses agent text event with runId and textChunk")
    func parsesAgentTextEvent() throws {
        let json: [String: Any] = [
            "type": "event",
            "runId": "run-abc",
            "payload": ["kind": "textChunk", "text": "Hello world"]
        ]

        let result = try OpenClawFrames.parseStreamEvent(from: json)
        #expect(result.runId == "run-abc")
        #expect(result.event == .textChunk("Hello world"))
    }

    @Test("parses agent done event returns nil event")
    func parsesAgentDoneEvent() throws {
        let json: [String: Any] = [
            "type": "event",
            "runId": "run-abc",
            "payload": ["kind": "done"]
        ]

        let result = try OpenClawFrames.parseStreamEvent(from: json)
        #expect(result.runId == "run-abc")
        #expect(result.event == nil)
    }

    @Test("parses agent error event")
    func parsesAgentErrorEvent() throws {
        let json: [String: Any] = [
            "type": "event",
            "runId": "run-abc",
            "payload": ["kind": "error", "message": "Something went wrong"]
        ]

        let result = try OpenClawFrames.parseStreamEvent(from: json)
        #expect(result.runId == "run-abc")
        #expect(result.event == .error("Something went wrong"))
    }

    // MARK: - Response Parsing

    @Test("parses success response frame for connect")
    func parsesSuccessResponseFrame() throws {
        let payload = """
        {"type":"res","id":"req-1","ok":true,"payload":{"connected":true}}
        """.data(using: .utf8)!

        let response = try OpenClawFrames.parseResponse(from: payload)
        #expect(response.id == "req-1")
        #expect(response.ok == true)
        #expect(response.errorMessage == nil)
    }

    @Test("parses error response frame")
    func parsesErrorResponseFrame() throws {
        let payload = """
        {"type":"res","id":"req-1","ok":false,"error":"Invalid token"}
        """.data(using: .utf8)!

        let response = try OpenClawFrames.parseResponse(from: payload)
        #expect(response.id == "req-1")
        #expect(response.ok == false)
        #expect(response.errorMessage == "Invalid token")
    }

    @Test("parses agents list from response payload")
    func parsesAgentsListFromResponse() throws {
        let payload = """
        {"type":"res","id":"req-2","ok":true,"payload":{"agents":[{"id":"agent-1","name":"Coder"},{"id":"agent-2","name":"Reviewer"}]}}
        """.data(using: .utf8)!

        let response = try OpenClawFrames.parseResponse(from: payload)
        #expect(response.ok == true)

        let entries = try OpenClawFrames.parseAgentsList(from: response)
        #expect(entries.count == 2)
        #expect(entries[0].id == "agent-1")
        #expect(entries[0].name == "Coder")
        #expect(entries[1].id == "agent-2")
        #expect(entries[1].name == "Reviewer")
    }
}
