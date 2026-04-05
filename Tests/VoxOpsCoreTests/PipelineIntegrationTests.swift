import Testing
import Foundation
@testable import VoxOpsCore

final class MockSTTBackend: STTBackend, @unchecked Sendable {
    let id = "mock"
    var status: BackendStatus = .ready
    var transcriptToReturn = "hello world"

    func start() async throws { status = .ready }
    func stop() async { status = .idle }

    func transcribe(audio: AudioBuffer) async throws -> TranscriptResult {
        return TranscriptResult(text: transcriptToReturn, confidence: 0.95, latencyMs: 10, backend: id)
    }
}

@Suite("Pipeline Integration")
struct PipelineIntegrationTests {
    @Test("audio buffer through STT and formatter produces clean text")
    func fullPipeline() async throws {
        let audio = AudioBuffer(pcmData: Data(repeating: 0, count: 32000))
        let backend = MockSTTBackend()
        backend.transcriptToReturn = "  hello world  this is a test  "
        let transcript = try await backend.transcribe(audio: audio)
        let formatter = RawFormatter()
        let formatted = formatter.format(transcript.text)
        #expect(formatted == "Hello world this is a test")
    }

    @Test("WAV round-trip produces valid file")
    func wavRoundTrip() throws {
        let original = Data(repeating: 42, count: 16000)
        let buffer = AudioBuffer(pcmData: original)
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try buffer.writeWAV(to: tempFile)
        let written = try Data(contentsOf: tempFile)
        #expect(written.count == 16044) // 44 header + 16000 data
        let pcmData = written.subdata(in: 44..<written.count)
        #expect(pcmData == original)
    }
}
