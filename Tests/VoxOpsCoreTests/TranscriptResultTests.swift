import Testing
import Foundation
@testable import VoxOpsCore

@Suite("TranscriptResult")
struct TranscriptResultTests {
    @Test("creates result with text and metadata")
    func create() {
        let result = TranscriptResult(text: "hello world", confidence: 0.95, latencyMs: 342, backend: "whisper.cpp")
        #expect(result.text == "hello world")
        #expect(result.confidence == 0.95)
        #expect(result.latencyMs == 342)
        #expect(result.backend == "whisper.cpp")
    }

    @Test("empty text is valid")
    func emptyText() {
        let result = TranscriptResult(text: "", confidence: 0.0, latencyMs: 0, backend: "test")
        #expect(result.text.isEmpty)
    }

    @Test("decodes from JSON")
    func decodeJSON() throws {
        let json = """
        {"text": "testing one two", "confidence": 0.88}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TranscriptJSON.self, from: json)
        #expect(decoded.text == "testing one two")
        #expect(decoded.confidence == 0.88)
    }
}
