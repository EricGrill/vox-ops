import Foundation

public final class WhisperCppBackend: STTBackend, @unchecked Sendable {
    public let id = "whisper.cpp"
    private let scriptPath: String
    private let modelPath: String
    private var sidecar: SidecarProcess?
    private let lock = NSLock()
    private var _status: BackendStatus = .idle

    public var status: BackendStatus {
        lock.lock()
        defer { lock.unlock() }
        return _status
    }

    public init(scriptPath: String, modelPath: String) {
        self.scriptPath = scriptPath
        self.modelPath = modelPath
    }

    public func start() async throws {
        lock.lock()
        defer { lock.unlock() }
        _status = .starting
        let proc = SidecarProcess(
            executablePath: "/bin/bash",
            arguments: [scriptPath],
            environment: ["WHISPER_MODEL": modelPath, "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]
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

        guard let jsonData = jsonLine.data(using: .utf8) else {
            lock.lock(); _status = .error("Invalid response encoding"); lock.unlock()
            throw SidecarError.encodingFailed
        }
        let decoded = try JSONDecoder().decode(TranscriptJSON.self, from: jsonData)
        lock.lock(); _status = .ready; lock.unlock()

        return TranscriptResult(text: decoded.text, confidence: decoded.confidence ?? 0.9, latencyMs: Int(elapsed * 1000), backend: id)
    }
}
