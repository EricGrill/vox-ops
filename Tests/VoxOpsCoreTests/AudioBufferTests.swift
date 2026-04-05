import Testing
import Foundation
@testable import VoxOpsCore

@Suite("AudioBuffer")
struct AudioBufferTests {
    @Test("creates buffer with correct properties")
    func createBuffer() {
        let data = Data(repeating: 0, count: 32000)
        let buffer = AudioBuffer(pcmData: data, sampleRate: 16000, channels: 1)
        #expect(buffer.sampleRate == 16000)
        #expect(buffer.channels == 1)
        #expect(buffer.pcmData.count == 32000)
    }

    @Test("calculates duration correctly")
    func duration() {
        let data = Data(repeating: 0, count: 64000) // 2 seconds at 16kHz mono 16-bit
        let buffer = AudioBuffer(pcmData: data, sampleRate: 16000, channels: 1)
        #expect(abs(buffer.duration - 2.0) < 0.01)
    }

    @Test("writes WAV file")
    func writeWAV() throws {
        let data = Data(repeating: 0, count: 32000)
        let buffer = AudioBuffer(pcmData: data, sampleRate: 16000, channels: 1)
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try buffer.writeWAV(to: tempFile)
        let written = try Data(contentsOf: tempFile)
        #expect(written.count == 32000 + 44)
        #expect(String(data: written[0..<4], encoding: .ascii) == "RIFF")
    }
}
