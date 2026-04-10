import Foundation

public final class SidecarProcess: @unchecked Sendable {
    private let executablePath: String
    private let arguments: [String]
    private let environment: [String: String]?
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private let lock = NSLock()

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning ?? false
    }

    public init(executablePath: String, arguments: [String] = [], environment: [String: String]? = nil) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = arguments
        if let env = environment { proc.environment = env }
        let stdin = Pipe()
        let stdout = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard let proc = process, proc.isRunning else { return }
        proc.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
    }

    public func writeLine(_ text: String) throws {
        lock.lock()
        guard let pipe = stdinPipe else { lock.unlock(); throw SidecarError.notRunning }
        lock.unlock()
        guard let data = (text + "\n").data(using: .utf8) else { throw SidecarError.encodingFailed }
        pipe.fileHandleForWriting.write(data)
    }

    public func readLine(timeoutSeconds: UInt64 = 30) async throws -> String {
        lock.lock()
        guard let pipe = stdoutPipe else { lock.unlock(); throw SidecarError.notRunning }
        lock.unlock()
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global().async {
                        let handle = pipe.fileHandleForReading
                        var accumulated = Data()
                        while true {
                            let byte = handle.readData(ofLength: 1)
                            if byte.isEmpty {
                                let result = String(data: accumulated, encoding: .utf8) ?? ""
                                continuation.resume(returning: result)
                                return
                            }
                            if byte.first == UInt8(ascii: "\n") {
                                let result = String(data: accumulated, encoding: .utf8) ?? ""
                                continuation.resume(returning: result)
                                return
                            }
                            accumulated.append(byte)
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                throw SidecarError.timeout
            }
            guard let result = try await group.next() else {
                throw SidecarError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    public func writeData(_ data: Data) throws {
        lock.lock()
        guard let pipe = stdinPipe else { lock.unlock(); throw SidecarError.notRunning }
        lock.unlock()
        pipe.fileHandleForWriting.write(data)
    }
}

public enum SidecarError: Error, Sendable {
    case notRunning
    case encodingFailed
    case timeout
    case processExited(code: Int32)
}
