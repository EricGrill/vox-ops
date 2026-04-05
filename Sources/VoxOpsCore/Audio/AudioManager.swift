import Foundation
import AVFoundation

public final class AudioManager: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var recordedData = Data()
    private let lock = NSLock()
    private var isRecording = false

    public init() {}

    public func startRecording() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isRecording else { return }
        recordedData = Data()
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        let busFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: busFormat) { [weak self] buffer, _ in
            guard let self else { return }
            if let converted = self.convert(buffer: buffer, to: recordingFormat) {
                self.lock.lock()
                self.recordedData.append(converted)
                self.lock.unlock()
            }
        }
        try engine.start()
        self.audioEngine = engine
        isRecording = true
    }

    public func stopRecording() -> AudioBuffer {
        lock.lock()
        defer { lock.unlock() }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        let data = recordedData
        recordedData = Data()
        return AudioBuffer(pcmData: data)
    }

    private func convert(buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> Data? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        var error: NSError?
        var isDone = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if isDone { outStatus.pointee = .noDataNow; return nil }
            isDone = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard error == nil, outputBuffer.frameLength > 0 else { return nil }
        let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: outputBuffer.int16ChannelData![0], count: byteCount)
    }
}

public struct AudioDevice: Sendable {
    public let id: String
    public let name: String
}
