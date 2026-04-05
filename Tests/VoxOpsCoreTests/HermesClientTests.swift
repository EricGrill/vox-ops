// Tests/VoxOpsCoreTests/HermesClientTests.swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("HermesClient")
struct HermesClientTests {

    // MARK: - HermesRequestBuilder

    @Test("builds chat completions request body")
    func buildsChatCompletionsRequestBody() throws {
        let messages = [
            ChatMessage(role: .system, content: "You are helpful."),
            ChatMessage(role: .user, content: "Hello!"),
        ]
        let data = try HermesRequestBuilder.chatCompletions(messages: messages, stream: true)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["model"] as? String == "hermes-agent")
        #expect(json["stream"] as? Bool == true)

        let msgs = json["messages"] as! [[String: String]]
        #expect(msgs.count == 2)
        #expect(msgs[0]["role"] == "system")
        #expect(msgs[0]["content"] == "You are helpful.")
        #expect(msgs[1]["role"] == "user")
        #expect(msgs[1]["content"] == "Hello!")
    }

    @Test("builds chat completions with stream false")
    func buildsChatCompletionsStreamFalse() throws {
        let messages = [ChatMessage(role: .user, content: "Hi")]
        let data = try HermesRequestBuilder.chatCompletions(messages: messages, stream: false)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["model"] as? String == "hermes-agent")
        #expect(json["stream"] as? Bool == false)
    }

    // MARK: - HermesSSEParser

    @Test("parses SSE data line into text chunk")
    func parsesSSEDataLineIntoTextChunk() {
        let line = #"data: {"id":"1","choices":[{"delta":{"content":"Hello"}}]}"#
        let event = HermesSSEParser.parseLine(line)
        #expect(event == .textChunk("Hello"))
    }

    @Test("parses SSE DONE sentinel as nil")
    func parsesDONESentinelAsNil() {
        let event = HermesSSEParser.parseLine("data: [DONE]")
        #expect(event == nil)
    }

    @Test("ignores non-data SSE lines")
    func ignoresNonDataSSELines() {
        #expect(HermesSSEParser.parseLine("") == nil)
        #expect(HermesSSEParser.parseLine(": keep-alive") == nil)
        #expect(HermesSSEParser.parseLine("event: message") == nil)
        #expect(HermesSSEParser.parseLine("id: 42") == nil)
    }

    @Test("parses SSE chunk with empty content still yields textChunk")
    func parsesSSEChunkWithEmptyContent() {
        let line = #"data: {"id":"2","choices":[{"delta":{"content":""}}]}"#
        let event = HermesSSEParser.parseLine(line)
        #expect(event == .textChunk(""))
    }

    @Test("parses SSE chunk with no content key returns nil (role-only delta)")
    func parsesSSEChunkWithNoContentKeyReturnsNil() {
        let line = #"data: {"id":"3","choices":[{"delta":{"role":"assistant"}}]}"#
        let event = HermesSSEParser.parseLine(line)
        #expect(event == nil)
    }
}
