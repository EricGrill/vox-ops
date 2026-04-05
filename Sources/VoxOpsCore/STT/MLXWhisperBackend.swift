import Foundation

public final class MLXWhisperBackend: STTBackend, @unchecked Sendable {
    public let id = "mlx-whisper"
    private let scriptPath: String
    private let pythonPath: String
    private let modelName: String
    private var sidecar: SidecarProcess?
    private var socketPath: String?
    private let lock = NSLock()
    private var _status: BackendStatus = .idle

    public var status: BackendStatus {
        lock.lock(); defer { lock.unlock() }; return _status
    }

    public init(scriptPath: String, pythonPath: String = "/usr/bin/python3", modelName: String = "mlx-community/whisper-small-mlx") {
        self.scriptPath = scriptPath
        self.pythonPath = pythonPath
        self.modelName = modelName
    }

    public func start() async throws {
        lock.lock(); defer { lock.unlock() }
        _status = .starting
        let sockPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxops-mlx-\(ProcessInfo.processInfo.processIdentifier).sock").path
        self.socketPath = sockPath
        let proc = SidecarProcess(
            executablePath: pythonPath,
            arguments: [scriptPath],
            environment: ["VOXOPS_SOCKET": sockPath, "WHISPER_MODEL": modelName]
        )
        try proc.start()
        sidecar = proc
        // Wait for socket to appear
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: sockPath) { _status = .ready; return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        _status = .error("Socket did not appear after 5s")
        throw SidecarError.timeout
    }

    public func stop() async {
        lock.lock(); defer { lock.unlock() }
        sidecar?.stop(); sidecar = nil
        if let sock = socketPath { try? FileManager.default.removeItem(atPath: sock) }
        socketPath = nil; _status = .idle
    }

    public func transcribe(audio: AudioBuffer) async throws -> TranscriptResult {
        lock.lock()
        if sidecar == nil || !(sidecar?.isRunning ?? false) { lock.unlock(); try await start() }
        else { lock.unlock() }

        lock.lock(); _status = .transcribing
        guard let sockPath = socketPath else { _status = .error("No socket path"); lock.unlock(); throw SidecarError.notRunning }
        lock.unlock()

        let startTime = CFAbsoluteTimeGetCurrent()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("voxops-\(UUID().uuidString).wav")
        try audio.writeWAV(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Connect to Unix socket and send path
        let jsonLine = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global().async {
                do {
                    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
                    guard fd >= 0 else { throw SidecarError.notRunning }
                    var addr = sockaddr_un()
                    addr.sun_family = sa_family_t(AF_UNIX)
                    let pathBytes = sockPath.utf8CString
                    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                        let bound = ptr.withMemoryRebound(to: CChar.self, capacity: 104) { $0 }
                        for (i, byte) in pathBytes.enumerated() where i < 104 { bound[i] = byte }
                    }
                    let addrLen = socklen_t(MemoryLayout.offset(of: \sockaddr_un.sun_path)! + sockPath.utf8.count + 1)
                    let connectResult = withUnsafePointer(to: &addr) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, addrLen) }
                    }
                    guard connectResult == 0 else { throw SidecarError.notRunning }

                    let message = tempFile.path + "\n"
                    message.utf8CString.withUnsafeBufferPointer { _ = write(fd, $0.baseAddress!, message.utf8.count) }

                    var response = Data()
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while true {
                        let n = read(fd, &buffer, buffer.count)
                        if n <= 0 { break }
                        response.append(contentsOf: buffer[0..<n])
                        if buffer[0..<n].contains(UInt8(ascii: "\n")) { break }
                    }
                    close(fd)
                    let line = String(data: response, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: line)
                } catch { continuation.resume(throwing: error) }
            }
        }

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
