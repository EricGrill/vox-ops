import Foundation
import Speech

public final class AppleSpeechBackend: STTBackend, @unchecked Sendable {
    public let id = "apple"
    private let locale: Locale
    private let lock = NSLock()
    private var _status: BackendStatus = .idle

    public var status: BackendStatus {
        lock.lock()
        defer { lock.unlock() }
        return _status
    }

    public init(language: String = "en-US") {
        self.locale = Locale(identifier: language)
    }

    public func start() async throws {
        let authStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard authStatus == .authorized else {
            lock.lock(); _status = .error("Speech recognition not authorized"); lock.unlock()
            throw AppleSpeechError.notAuthorized
        }
        guard SFSpeechRecognizer(locale: locale) != nil else {
            lock.lock(); _status = .error("Locale \(locale.identifier) not supported"); lock.unlock()
            throw AppleSpeechError.localeUnsupported
        }
        lock.lock(); _status = .ready; lock.unlock()
    }

    public func stop() async {
        lock.lock(); _status = .idle; lock.unlock()
    }

    public func transcribe(audio: AudioBuffer) async throws -> TranscriptResult {
        lock.lock()
        if case .ready = _status {
            // already ready
        } else {
            lock.unlock()
            try await start()
            lock.lock()
        }
        _status = .transcribing
        lock.unlock()

        let startTime = CFAbsoluteTimeGetCurrent()

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxops-\(UUID().uuidString).wav")
        try audio.writeWAV(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            lock.lock(); _status = .error("Recognizer unavailable"); lock.unlock()
            throw AppleSpeechError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: tempFile)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let result: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { cont in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else if let result = result, result.isFinal {
                    cont.resume(returning: result)
                }
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let text = result.bestTranscription.formattedString
        let confidence = Double(result.bestTranscription.segments.map(\.confidence).reduce(0, +))
            / Double(max(result.bestTranscription.segments.count, 1))

        lock.lock(); _status = .ready; lock.unlock()

        return TranscriptResult(
            text: text,
            confidence: confidence,
            latencyMs: Int(elapsed * 1000),
            backend: id
        )
    }
}

public enum AppleSpeechError: Error, LocalizedError {
    case notAuthorized
    case localeUnsupported
    case recognizerUnavailable

    public var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Speech recognition not authorized"
        case .localeUnsupported: return "Selected language not supported by Apple Speech"
        case .recognizerUnavailable: return "Speech recognizer unavailable"
        }
    }
}
