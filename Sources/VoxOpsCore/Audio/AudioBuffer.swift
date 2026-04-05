import Foundation

public struct AudioBuffer: Sendable {
    public let pcmData: Data
    public let sampleRate: Int
    public let channels: Int
    public let bitsPerSample: Int

    public init(pcmData: Data, sampleRate: Int = 16000, channels: Int = 1, bitsPerSample: Int = 16) {
        self.pcmData = pcmData
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
    }

    public var duration: Double {
        let bytesPerSample = bitsPerSample / 8
        let bytesPerSecond = sampleRate * channels * bytesPerSample
        return Double(pcmData.count) / Double(bytesPerSecond)
    }

    public func writeWAV(to url: URL) throws {
        var wav = Data()
        let dataSize = UInt32(pcmData.count)
        let fileSize = dataSize + 36

        wav.append(contentsOf: "RIFF".utf8)
        wav.append(littleEndian: fileSize)
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(littleEndian: UInt32(16))
        wav.append(littleEndian: UInt16(1))
        wav.append(littleEndian: UInt16(channels))
        wav.append(littleEndian: UInt32(sampleRate))
        let byteRate = UInt32(sampleRate * channels * bitsPerSample / 8)
        wav.append(littleEndian: byteRate)
        wav.append(littleEndian: UInt16(channels * bitsPerSample / 8))
        wav.append(littleEndian: UInt16(bitsPerSample))
        wav.append(contentsOf: "data".utf8)
        wav.append(littleEndian: dataSize)
        wav.append(pcmData)

        try wav.write(to: url)
    }
}

extension Data {
    mutating func append(littleEndian value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }
    mutating func append(littleEndian value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}
