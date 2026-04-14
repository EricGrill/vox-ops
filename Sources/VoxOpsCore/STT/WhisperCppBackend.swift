import Foundation

public final class WhisperCppBackend: STTBackend, @unchecked Sendable {
    public let id = "whisper.cpp"
    private let scriptPath: String
    private let modelPath: String
    private let initialPrompt: String?
    private let language: String
    private var sidecar: SidecarProcess?
    private let lock = NSLock()
    private var _status: BackendStatus = .idle

    public var status: BackendStatus {
        lock.lock()
        defer { lock.unlock() }
        return _status
    }

    public init(scriptPath: String, modelPath: String, initialPrompt: String? = nil, language: String = "en") {
        self.scriptPath = scriptPath
        self.modelPath = modelPath
        self.initialPrompt = initialPrompt
        self.language = language
    }

    public func start() async throws {
        lock.lock()
        defer { lock.unlock() }
        _status = .starting
        var env = ["WHISPER_MODEL": modelPath, "WHISPER_LANG": language, "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]
        if let prompt = initialPrompt, !prompt.isEmpty {
            env["WHISPER_PROMPT"] = prompt
        }
        let proc = SidecarProcess(
            executablePath: "/bin/bash",
            arguments: [scriptPath],
            environment: env
        )
        try proc.start()
        sidecar = proc
        _status = .ready
    }

    public func stop() async {
        lock.lock()
        defer { lock.unlock() }
        sidecar?.stop()
        sidecar = nil
        _status = .idle
    }

    public func transcribe(audio: AudioBuffer) async throws -> TranscriptResult {
        lock.lock()
        if sidecar == nil || !(sidecar?.isRunning ?? false) {
            lock.unlock()
            try await start()
        } else { lock.unlock() }

        lock.lock()
        _status = .transcribing
        lock.unlock()

        let startTime = CFAbsoluteTimeGetCurrent()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("voxops-\(UUID().uuidString).wav")
        try audio.writeWAV(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        lock.lock()
        guard let proc = sidecar else { lock.unlock(); throw SidecarError.notRunning }
        lock.unlock()

        try proc.writeLine(tempFile.path)
        let jsonLine = try await proc.readLine()
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        guard let jsonData = jsonLine.data(using: .utf8), !jsonData.isEmpty else {
            lock.lock(); _status = .error("Empty response from sidecar"); lock.unlock()
            throw SidecarError.encodingFailed
        }
        guard let decoded = try? JSONDecoder().decode(TranscriptJSON.self, from: jsonData) else {
            lock.lock(); _status = .error("Bad JSON: \(String(jsonLine.prefix(80)))"); lock.unlock()
            throw SidecarError.encodingFailed
        }
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            lock.lock(); _status = .ready; lock.unlock()
            return TranscriptResult(text: "", confidence: 0, latencyMs: Int(elapsed * 1000), backend: id)
        }
        lock.lock(); _status = .ready; lock.unlock()

        return TranscriptResult(text: text, confidence: decoded.confidence ?? 0.9, latencyMs: Int(elapsed * 1000), backend: id)
    }
}
