import Foundation

public enum BackendStatus: Sendable {
    case idle
    case starting
    case ready
    case transcribing
    case error(String)
}

public protocol STTBackend: Sendable {
    var id: String { get }
    var status: BackendStatus { get }
    func transcribe(audio: AudioBuffer) async throws -> TranscriptResult
    func start() async throws
    func stop() async
}
