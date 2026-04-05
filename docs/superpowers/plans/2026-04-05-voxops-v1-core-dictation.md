# VoxOps V1: Core Dictation Engine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working push-to-talk dictation engine for macOS that captures audio, transcribes locally via whisper.cpp or MLX Whisper, and injects raw text at the cursor in any app.

**Architecture:** Native Swift + SwiftUI menu bar app. Core logic (hotkey, audio, injection) runs in the main app process. STT engines run as managed sidecar processes communicating via stdin/stdout (whisper.cpp) or Unix domain socket (MLX Whisper). SQLite for settings persistence.

**Tech Stack:** Swift 5.9+, SwiftUI, AVFoundation, CoreAudio, CoreGraphics (CGEvent), Accessibility API (AXUIElement), SQLite (via swift-sqlite or GRDB), whisper.cpp CLI, MLX Whisper (Python)

**Spec:** `docs/superpowers/specs/2026-04-05-voxops-design.md`

---

## File Structure

```
VoxOps/
├── Package.swift                           # SPM package for core library
├── Sources/
│   └── VoxOpsCore/
│       ├── Storage/
│       │   ├── Database.swift              # SQLite connection, migrations, schema
│       │   └── SettingsStore.swift          # Settings CRUD, defaults, observation
│       ├── Sidecar/
│       │   └── SidecarProcess.swift         # Generic sidecar lifecycle (spawn, health, restart, kill)
│       ├── Audio/
│       │   ├── AudioBuffer.swift            # PCM audio data container (16kHz mono)
│       │   └── AudioManager.swift           # AVFoundation mic recording, start/stop, mic listing
│       ├── STT/
│       │   ├── STTBackend.swift             # Protocol: transcribe(audio:) async throws -> TranscriptResult
│       │   ├── TranscriptResult.swift       # Transcript text, segments, confidence, latency
│       │   ├── WhisperCppBackend.swift      # whisper.cpp sidecar: spawn CLI, pipe audio, parse JSON
│       │   └── MLXWhisperBackend.swift      # MLX Whisper sidecar: Unix socket, send audio, receive JSON
│       ├── Pipeline/
│       │   └── RawFormatter.swift           # Minimal cleanup: capitalize sentences, basic punctuation
│       ├── Injection/
│       │   ├── TextInjector.swift           # Protocol + coordinator: try AX, fall back to clipboard
│       │   ├── AccessibilityInjector.swift  # AXUIElement: find focused element, set AXValue
│       │   └── ClipboardInjector.swift      # Save clipboard, set text, Cmd+V, restore clipboard
│       └── Hotkey/
│           └── HotkeyManager.swift          # CGEvent tap: global key down/up, configurable key
├── Tests/
│   └── VoxOpsCoreTests/
│       ├── DatabaseTests.swift
│       ├── SettingsStoreTests.swift
│       ├── SidecarProcessTests.swift
│       ├── AudioBufferTests.swift
│       ├── RawFormatterTests.swift
│       ├── TranscriptResultTests.swift
│       ├── ClipboardInjectorTests.swift
│       └── WhisperCppBackendTests.swift
├── VoxOpsApp/
│   ├── VoxOpsApp.swift                      # @main, MenuBarExtra, app lifecycle
│   ├── AppState.swift                       # ObservableObject: orchestrates pipeline, holds state
│   ├── Views/
│   │   ├── MenuBarView.swift                # MenuBarExtra dropdown content
│   │   ├── HUDWindow.swift                  # NSPanel subclass, nonactivating, draggable
│   │   ├── HUDOrbView.swift                 # SwiftUI orb: color, pulse, spin per state
│   │   └── SettingsView.swift               # Basic settings: hotkey, mic, model, backend
│   └── VoxOpsApp.entitlements               # Accessibility, microphone, network (model download)
├── Scripts/
│   ├── whisper-sidecar/
│   │   ├── README.md                        # Build instructions for whisper.cpp
│   │   └── run.sh                           # Wrapper: accepts audio path on stdin, outputs JSON
│   └── mlx-whisper-sidecar/
│       ├── requirements.txt                 # mlx-whisper, numpy
│       ├── server.py                        # Unix socket server: receive audio, return transcript JSON
│       └── README.md                        # Setup instructions
└── Resources/
    └── default-settings.json                # Shipped defaults for first launch
```

**Key boundaries:**
- `VoxOpsCore` is a pure Swift package — testable without the app, no AppKit/SwiftUI dependency
- `VoxOpsApp` is the macOS app target — imports VoxOpsCore, owns UI and app lifecycle
- Sidecar scripts are standalone — tested independently, communicate via well-defined protocols
- Each component communicates through protocols, not concrete types

---

## Task 1: Project Scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/VoxOpsCore/.gitkeep`
- Create: `Tests/VoxOpsCoreTests/.gitkeep`
- Create: `VoxOpsApp/VoxOpsApp.swift`
- Create: `VoxOpsApp/VoxOpsApp.entitlements`
- Create: `.gitignore`

- [ ] **Step 1: Initialize Swift package**

Create `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoxOps",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoxOpsCore", targets: ["VoxOpsCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "VoxOpsCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "VoxOpsCoreTests",
            dependencies: ["VoxOpsCore"]
        ),
    ]
)
```

- [ ] **Step 2: Create directory structure**

```bash
mkdir -p Sources/VoxOpsCore/{Storage,Sidecar,Audio,STT,Pipeline,Injection,Hotkey}
mkdir -p Tests/VoxOpsCoreTests
mkdir -p VoxOpsApp/Views
mkdir -p Scripts/{whisper-sidecar,mlx-whisper-sidecar}
mkdir -p Resources
```

- [ ] **Step 3: Create .gitignore**

```
.DS_Store
.build/
.swiftpm/
*.xcodeproj
*.xcworkspace
DerivedData/
*.o
*.a
__pycache__/
*.pyc
.venv/
Models/
```

- [ ] **Step 4: Create minimal app entry point**

Create `VoxOpsApp/VoxOpsApp.swift`:

```swift
import SwiftUI

@main
struct VoxOpsApp: App {
    var body: some Scene {
        MenuBarExtra("VoxOps", systemImage: "waveform.circle") {
            Text("VoxOps — Starting...")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
```

- [ ] **Step 5: Verify package resolves**

Run: `swift package resolve`
Expected: Dependencies resolve successfully

- [ ] **Step 6: Verify build**

Run: `swift build`
Expected: Build succeeds (core library only — app target is Xcode-only for now)

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/ Tests/ VoxOpsApp/ Scripts/ Resources/ .gitignore
git commit -m "feat: scaffold VoxOps project structure with SPM and GRDB"
```

---

## Task 2: SQLite Storage Layer

**Files:**
- Create: `Sources/VoxOpsCore/Storage/Database.swift`
- Create: `Sources/VoxOpsCore/Storage/SettingsStore.swift`
- Create: `Tests/VoxOpsCoreTests/DatabaseTests.swift`
- Create: `Tests/VoxOpsCoreTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write failing test for database creation**

Create `Tests/VoxOpsCoreTests/DatabaseTests.swift`:

```swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("Database")
struct DatabaseTests {
    @Test("creates database and runs migrations")
    func createDatabase() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let db = try Database(directory: tempDir)
        let version = try db.schemaVersion()
        #expect(version > 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DatabaseTests`
Expected: FAIL — `Database` type not found

- [ ] **Step 3: Implement Database**

Create `Sources/VoxOpsCore/Storage/Database.swift`:

```swift
import Foundation
import GRDB

public final class Database: Sendable {
    private let dbPool: DatabasePool

    public init(directory: URL) throws {
        let dbPath = directory.appendingPathComponent("voxops.sqlite").path
        dbPool = try DatabasePool(path: dbPath)
        try migrate()
    }

    /// For testing with in-memory database
    public init(inMemory: Bool = true) throws {
        dbPool = try DatabasePool(path: ":memory:")
        try migrate()
    }

    public func reader() -> DatabasePool { dbPool }
    public func writer() -> DatabasePool { dbPool }

    public func schemaVersion() throws -> Int {
        try dbPool.read { db in
            try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
        }
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_settings") { db in
            try db.create(table: "settings") { t in
                t.primaryKey("key", .text).notNull()
                t.column("value", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }

        try migrator.migrate(dbPool)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DatabaseTests`
Expected: PASS

- [ ] **Step 5: Write failing test for SettingsStore**

Create `Tests/VoxOpsCoreTests/SettingsStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("SettingsStore")
struct SettingsStoreTests {
    @Test("get returns default when key not set")
    func getDefault() throws {
        let db = try Database(inMemory: true)
        let store = SettingsStore(database: db)
        let value = try store.getString("nonexistent")
        #expect(value == nil)
    }

    @Test("set and get round-trips string value")
    func setAndGet() throws {
        let db = try Database(inMemory: true)
        let store = SettingsStore(database: db)
        try store.setString("hotkey", value: "Option+Space")
        let value = try store.getString("hotkey")
        #expect(value == "Option+Space")
    }

    @Test("set overwrites existing value")
    func overwrite() throws {
        let db = try Database(inMemory: true)
        let store = SettingsStore(database: db)
        try store.setString("hotkey", value: "Option+Space")
        try store.setString("hotkey", value: "Fn")
        let value = try store.getString("hotkey")
        #expect(value == "Fn")
    }
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `swift test --filter SettingsStoreTests`
Expected: FAIL — `SettingsStore` type not found

- [ ] **Step 7: Implement SettingsStore**

Create `Sources/VoxOpsCore/Storage/SettingsStore.swift`:

```swift
import Foundation
import GRDB

public final class SettingsStore: Sendable {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func getString(_ key: String) throws -> String? {
        try database.reader().read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM settings WHERE key = ?",
                arguments: [key]
            )
        }
    }

    public func setString(_ key: String, value: String) throws {
        try database.writer().write { db in
            try db.execute(
                sql: """
                    INSERT INTO settings (key, value, updatedAt)
                    VALUES (?, ?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = ?, updatedAt = ?
                    """,
                arguments: [key, value, Date(), value, Date()]
            )
        }
    }
}
```

- [ ] **Step 8: Run all storage tests**

Run: `swift test --filter "DatabaseTests|SettingsStoreTests"`
Expected: All PASS

- [ ] **Step 9: Commit**

```bash
git add Sources/VoxOpsCore/Storage/ Tests/VoxOpsCoreTests/DatabaseTests.swift Tests/VoxOpsCoreTests/SettingsStoreTests.swift
git commit -m "feat: add SQLite storage layer with GRDB, settings CRUD"
```

---

## Task 3: Audio Buffer and Recording

**Files:**
- Create: `Sources/VoxOpsCore/Audio/AudioBuffer.swift`
- Create: `Sources/VoxOpsCore/Audio/AudioManager.swift`
- Create: `Tests/VoxOpsCoreTests/AudioBufferTests.swift`

- [ ] **Step 1: Write failing test for AudioBuffer**

Create `Tests/VoxOpsCoreTests/AudioBufferTests.swift`:

```swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("AudioBuffer")
struct AudioBufferTests {
    @Test("creates buffer with correct properties")
    func createBuffer() {
        let data = Data(repeating: 0, count: 32000) // 1 second at 16kHz mono 16-bit
        let buffer = AudioBuffer(pcmData: data, sampleRate: 16000, channels: 1)
        #expect(buffer.sampleRate == 16000)
        #expect(buffer.channels == 1)
        #expect(buffer.pcmData.count == 32000)
    }

    @Test("calculates duration correctly")
    func duration() {
        // 16kHz, mono, 16-bit = 32000 bytes per second
        let data = Data(repeating: 0, count: 64000) // 2 seconds
        let buffer = AudioBuffer(pcmData: data, sampleRate: 16000, channels: 1)
        #expect(abs(buffer.duration - 2.0) < 0.01)
    }

    @Test("writes WAV file")
    func writeWAV() throws {
        let data = Data(repeating: 0, count: 32000)
        let buffer = AudioBuffer(pcmData: data, sampleRate: 16000, channels: 1)

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        try buffer.writeWAV(to: tempFile)
        let written = try Data(contentsOf: tempFile)
        // WAV header is 44 bytes
        #expect(written.count == 32000 + 44)
        // Check RIFF header
        #expect(String(data: written[0..<4], encoding: .ascii) == "RIFF")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AudioBufferTests`
Expected: FAIL — `AudioBuffer` type not found

- [ ] **Step 3: Implement AudioBuffer**

Create `Sources/VoxOpsCore/Audio/AudioBuffer.swift`:

```swift
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

    /// Duration in seconds
    public var duration: Double {
        let bytesPerSample = bitsPerSample / 8
        let bytesPerSecond = sampleRate * channels * bytesPerSample
        return Double(pcmData.count) / Double(bytesPerSecond)
    }

    /// Write as WAV file (required by whisper.cpp sidecar)
    public func writeWAV(to url: URL) throws {
        var wav = Data()
        let dataSize = UInt32(pcmData.count)
        let fileSize = dataSize + 36

        // RIFF header
        wav.append(contentsOf: "RIFF".utf8)
        wav.append(littleEndian: fileSize)
        wav.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(littleEndian: UInt32(16))           // chunk size
        wav.append(littleEndian: UInt16(1))            // PCM format
        wav.append(littleEndian: UInt16(channels))
        wav.append(littleEndian: UInt32(sampleRate))
        let byteRate = UInt32(sampleRate * channels * bitsPerSample / 8)
        wav.append(littleEndian: byteRate)
        wav.append(littleEndian: UInt16(channels * bitsPerSample / 8)) // block align
        wav.append(littleEndian: UInt16(bitsPerSample))

        // data chunk
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AudioBufferTests`
Expected: All PASS

- [ ] **Step 5: Implement AudioManager**

Create `Sources/VoxOpsCore/Audio/AudioManager.swift`:

```swift
import Foundation
import AVFoundation

/// Manages microphone recording. Records 16kHz mono PCM audio.
/// Start/stop are called by HotkeyManager on key down/up.
public final class AudioManager: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var recordedData = Data()
    private let lock = NSLock()
    private var isRecording = false

    public init() {}

    /// List available input devices
    public func availableMicrophones() -> [AudioDevice] {
        // AVAudioEngine uses the system default; for device listing
        // we use CoreAudio. Simplified here — full impl uses AudioObjectGetPropertyData.
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let name = inputNode.name(forInputBus: 0) ?? "Default"
        return [AudioDevice(id: "default", name: name)]
    }

    /// Start recording from the microphone
    public func startRecording() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isRecording else { return }

        recordedData = Data()
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!

        let busFormat = inputNode.outputFormat(forBus: 0)

        // Install tap at the hardware format, we'll convert later
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: busFormat) { [weak self] buffer, _ in
            guard let self else { return }
            // Convert to 16kHz mono Int16
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

    /// Stop recording and return the captured audio
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
        let frameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate
        )
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }

        var error: NSError?
        var isDone = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if isDone {
                outStatus.pointee = .noDataNow
                return nil
            }
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
```

Note: AudioManager cannot be meaningfully unit-tested without a microphone. It is integration-tested manually and via the full pipeline. The AudioBuffer type carries all the testable logic.

- [ ] **Step 6: Run all tests**

Run: `swift test`
Expected: All PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/VoxOpsCore/Audio/ Tests/VoxOpsCoreTests/AudioBufferTests.swift
git commit -m "feat: add AudioBuffer with WAV export and AudioManager for mic recording"
```

---

## Task 4: Sidecar Process Manager

**Files:**
- Create: `Sources/VoxOpsCore/Sidecar/SidecarProcess.swift`
- Create: `Tests/VoxOpsCoreTests/SidecarProcessTests.swift`

- [ ] **Step 1: Write failing test for SidecarProcess**

Create `Tests/VoxOpsCoreTests/SidecarProcessTests.swift`:

```swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("SidecarProcess")
struct SidecarProcessTests {
    @Test("launches process and reads stdout")
    func launchAndRead() async throws {
        let sidecar = SidecarProcess(
            executablePath: "/bin/echo",
            arguments: ["hello voxops"]
        )
        try sidecar.start()
        let output = try await sidecar.readLine()
        #expect(output == "hello voxops")
        sidecar.stop()
    }

    @Test("reports not running after stop")
    func stopStatus() throws {
        let sidecar = SidecarProcess(
            executablePath: "/bin/cat",
            arguments: []
        )
        try sidecar.start()
        #expect(sidecar.isRunning == true)
        sidecar.stop()
        // Give process time to terminate
        Thread.sleep(forTimeInterval: 0.1)
        #expect(sidecar.isRunning == false)
    }

    @Test("writes to stdin and reads response")
    func stdinStdout() async throws {
        // cat echoes stdin to stdout
        let sidecar = SidecarProcess(
            executablePath: "/bin/cat",
            arguments: []
        )
        try sidecar.start()
        try sidecar.writeLine("ping")
        let output = try await sidecar.readLine()
        #expect(output == "ping")
        sidecar.stop()
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SidecarProcessTests`
Expected: FAIL — `SidecarProcess` type not found

- [ ] **Step 3: Implement SidecarProcess**

Create `Sources/VoxOpsCore/Sidecar/SidecarProcess.swift`:

```swift
import Foundation

/// Manages a long-running child process with stdin/stdout communication.
/// Used for STT sidecar backends (whisper.cpp CLI, MLX Whisper Python server).
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

    public init(
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil
    ) {
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
        if let env = environment {
            proc.environment = env
        }

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

    /// Write a line to the process stdin (appends newline)
    public func writeLine(_ text: String) throws {
        lock.lock()
        guard let pipe = stdinPipe else {
            lock.unlock()
            throw SidecarError.notRunning
        }
        lock.unlock()

        guard let data = (text + "\n").data(using: .utf8) else {
            throw SidecarError.encodingFailed
        }
        pipe.fileHandleForWriting.write(data)
    }

    /// Read a line from the process stdout
    public func readLine() async throws -> String {
        guard let pipe = stdoutPipe else {
            throw SidecarError.notRunning
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let handle = pipe.fileHandleForReading
                var accumulated = Data()

                while true {
                    let byte = handle.readData(ofLength: 1)
                    if byte.isEmpty {
                        // EOF
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

    /// Write raw data to stdin
    public func writeData(_ data: Data) throws {
        lock.lock()
        guard let pipe = stdinPipe else {
            lock.unlock()
            throw SidecarError.notRunning
        }
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
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter SidecarProcessTests`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/VoxOpsCore/Sidecar/ Tests/VoxOpsCoreTests/SidecarProcessTests.swift
git commit -m "feat: add SidecarProcess for managing STT child processes"
```

---

## Task 5: STT Protocol and TranscriptResult

**Files:**
- Create: `Sources/VoxOpsCore/STT/STTBackend.swift`
- Create: `Sources/VoxOpsCore/STT/TranscriptResult.swift`
- Create: `Tests/VoxOpsCoreTests/TranscriptResultTests.swift`

- [ ] **Step 1: Write failing test for TranscriptResult**

Create `Tests/VoxOpsCoreTests/TranscriptResultTests.swift`:

```swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("TranscriptResult")
struct TranscriptResultTests {
    @Test("creates result with text and metadata")
    func create() {
        let result = TranscriptResult(
            text: "hello world",
            confidence: 0.95,
            latencyMs: 342,
            backend: "whisper.cpp"
        )
        #expect(result.text == "hello world")
        #expect(result.confidence == 0.95)
        #expect(result.latencyMs == 342)
        #expect(result.backend == "whisper.cpp")
    }

    @Test("empty text is valid")
    func emptyText() {
        let result = TranscriptResult(text: "", confidence: 0.0, latencyMs: 0, backend: "test")
        #expect(result.text.isEmpty)
    }

    @Test("decodes from JSON")
    func decodeJSON() throws {
        let json = """
        {"text": "testing one two", "confidence": 0.88}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TranscriptJSON.self, from: json)
        #expect(decoded.text == "testing one two")
        #expect(decoded.confidence == 0.88)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TranscriptResultTests`
Expected: FAIL — types not found

- [ ] **Step 3: Implement TranscriptResult and STTBackend protocol**

Create `Sources/VoxOpsCore/STT/TranscriptResult.swift`:

```swift
import Foundation

/// Result from an STT transcription
public struct TranscriptResult: Sendable {
    public let text: String
    public let confidence: Double
    public let latencyMs: Int
    public let backend: String

    public init(text: String, confidence: Double, latencyMs: Int, backend: String) {
        self.text = text
        self.confidence = confidence
        self.latencyMs = latencyMs
        self.backend = backend
    }
}

/// JSON structure returned by STT sidecars
public struct TranscriptJSON: Codable, Sendable {
    public let text: String
    public let confidence: Double?

    public init(text: String, confidence: Double? = nil) {
        self.text = text
        self.confidence = confidence
    }
}
```

Create `Sources/VoxOpsCore/STT/STTBackend.swift`:

```swift
import Foundation

/// Status of an STT backend sidecar
public enum BackendStatus: Sendable {
    case idle
    case starting
    case ready
    case transcribing
    case error(String)
}

/// Protocol for all STT backends. Both whisper.cpp and MLX Whisper conform.
public protocol STTBackend: Sendable {
    var id: String { get }
    var status: BackendStatus { get }

    /// Transcribe audio and return final result
    func transcribe(audio: AudioBuffer) async throws -> TranscriptResult

    /// Start the backend (lazy — called on first use)
    func start() async throws

    /// Stop the backend
    func stop() async
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter TranscriptResultTests`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/VoxOpsCore/STT/STTBackend.swift Sources/VoxOpsCore/STT/TranscriptResult.swift Tests/VoxOpsCoreTests/TranscriptResultTests.swift
git commit -m "feat: add STTBackend protocol and TranscriptResult types"
```

---

## Task 6: whisper.cpp Backend

**Files:**
- Create: `Sources/VoxOpsCore/STT/WhisperCppBackend.swift`
- Create: `Scripts/whisper-sidecar/run.sh`
- Create: `Scripts/whisper-sidecar/README.md`
- Create: `Tests/VoxOpsCoreTests/WhisperCppBackendTests.swift`

- [ ] **Step 1: Create the whisper.cpp sidecar script**

Create `Scripts/whisper-sidecar/run.sh`:

```bash
#!/bin/bash
# VoxOps whisper.cpp sidecar
# Reads WAV file paths from stdin (one per line), outputs JSON transcripts to stdout.
# Requires: whisper-cpp CLI installed (brew install whisper-cpp or built from source)
#
# Protocol:
#   Input:  /path/to/audio.wav\n
#   Output: {"text": "transcribed text", "confidence": 0.95}\n
#
# Environment:
#   WHISPER_MODEL — path to .bin model file (required)
#   WHISPER_CLI   — path to whisper-cli binary (default: whisper-cli)

set -euo pipefail

WHISPER_CLI="${WHISPER_CLI:-whisper-cli}"
WHISPER_MODEL="${WHISPER_MODEL:?WHISPER_MODEL environment variable required}"

while IFS= read -r wav_path; do
    if [ -z "$wav_path" ]; then continue; fi

    # Run whisper, capture output, format as JSON
    transcript=$("$WHISPER_CLI" \
        --model "$WHISPER_MODEL" \
        --file "$wav_path" \
        --output-json \
        --no-timestamps \
        --language en \
        2>/dev/null)

    # Extract text from whisper JSON output
    text=$(echo "$transcript" | python3 -c "
import sys, json
data = json.load(sys.stdin)
segments = data.get('transcription', [])
text = ' '.join(s.get('text', '').strip() for s in segments).strip()
print(json.dumps({'text': text, 'confidence': 0.9}))
" 2>/dev/null || echo '{"text": "", "confidence": 0.0}')

    echo "$text"
done
```

```bash
chmod +x Scripts/whisper-sidecar/run.sh
```

- [ ] **Step 2: Create README for sidecar setup**

Create `Scripts/whisper-sidecar/README.md`:

```markdown
# whisper.cpp Sidecar

## Requirements

- whisper-cli: `brew install whisper-cpp` or build from source
- A Whisper model file (.bin format)

## Download a model

```bash
# Small model (~500MB, good balance of speed/accuracy)
curl -L -o ~/Library/Application\ Support/VoxOps/Models/ggml-small.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
```

## Test manually

```bash
WHISPER_MODEL=~/Library/Application\ Support/VoxOps/Models/ggml-small.bin \
echo "/path/to/test.wav" | ./run.sh
```
```

- [ ] **Step 3: Write failing test for WhisperCppBackend**

Create `Tests/VoxOpsCoreTests/WhisperCppBackendTests.swift`:

```swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("WhisperCppBackend")
struct WhisperCppBackendTests {
    @Test("has correct id")
    func backendId() {
        let backend = WhisperCppBackend(
            scriptPath: "/nonexistent/run.sh",
            modelPath: "/nonexistent/model.bin"
        )
        #expect(backend.id == "whisper.cpp")
    }

    @Test("starts in idle status")
    func initialStatus() {
        let backend = WhisperCppBackend(
            scriptPath: "/nonexistent/run.sh",
            modelPath: "/nonexistent/model.bin"
        )
        if case .idle = backend.status {
            // correct
        } else {
            Issue.record("Expected idle status")
        }
    }
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `swift test --filter WhisperCppBackendTests`
Expected: FAIL — `WhisperCppBackend` not found

- [ ] **Step 5: Implement WhisperCppBackend**

Create `Sources/VoxOpsCore/STT/WhisperCppBackend.swift`:

```swift
import Foundation

/// whisper.cpp sidecar backend.
/// Spawns the run.sh script, sends WAV file paths via stdin, reads JSON transcripts from stdout.
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
            environment: [
                "WHISPER_MODEL": modelPath,
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            ]
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
        } else {
            lock.unlock()
        }

        lock.lock()
        _status = .transcribing
        lock.unlock()

        let startTime = CFAbsoluteTimeGetCurrent()

        // Write audio to temp WAV file
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxops-\(UUID().uuidString).wav")
        try audio.writeWAV(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Send file path to sidecar
        lock.lock()
        guard let proc = sidecar else {
            lock.unlock()
            throw SidecarError.notRunning
        }
        lock.unlock()

        try proc.writeLine(tempFile.path)

        // Read JSON response
        let jsonLine = try await proc.readLine()
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        guard let jsonData = jsonLine.data(using: .utf8) else {
            lock.lock()
            _status = .error("Invalid response encoding")
            lock.unlock()
            throw SidecarError.encodingFailed
        }

        let decoded = try JSONDecoder().decode(TranscriptJSON.self, from: jsonData)

        lock.lock()
        _status = .ready
        lock.unlock()

        return TranscriptResult(
            text: decoded.text,
            confidence: decoded.confidence ?? 0.9,
            latencyMs: Int(elapsed * 1000),
            backend: id
        )
    }
}
```

- [ ] **Step 6: Run tests**

Run: `swift test --filter WhisperCppBackendTests`
Expected: All PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/VoxOpsCore/STT/WhisperCppBackend.swift Scripts/whisper-sidecar/ Tests/VoxOpsCoreTests/WhisperCppBackendTests.swift
git commit -m "feat: add whisper.cpp STT backend with sidecar script"
```

---

## Task 7: MLX Whisper Backend

**Files:**
- Create: `Sources/VoxOpsCore/STT/MLXWhisperBackend.swift`
- Create: `Scripts/mlx-whisper-sidecar/server.py`
- Create: `Scripts/mlx-whisper-sidecar/requirements.txt`
- Create: `Scripts/mlx-whisper-sidecar/README.md`

- [ ] **Step 1: Create the MLX Whisper sidecar Python server**

Create `Scripts/mlx-whisper-sidecar/requirements.txt`:

```
mlx-whisper>=0.4
numpy
```

Create `Scripts/mlx-whisper-sidecar/server.py`:

```python
#!/usr/bin/env python3
"""
VoxOps MLX Whisper sidecar server.
Listens on a Unix domain socket, receives audio file paths, returns JSON transcripts.

Protocol:
  Client sends: /path/to/audio.wav\n
  Server sends: {"text": "transcribed text", "confidence": 0.95}\n

Environment:
  VOXOPS_SOCKET — path to Unix domain socket (required)
  WHISPER_MODEL — model name for mlx-whisper (default: mlx-community/whisper-small-mlx)
"""

import json
import os
import socket
import sys

import mlx_whisper


def main():
    socket_path = os.environ.get("VOXOPS_SOCKET")
    if not socket_path:
        print("VOXOPS_SOCKET environment variable required", file=sys.stderr)
        sys.exit(1)

    model_name = os.environ.get("WHISPER_MODEL", "mlx-community/whisper-small-mlx")

    # Clean up stale socket
    if os.path.exists(socket_path):
        os.unlink(socket_path)

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(socket_path)
    sock.listen(1)

    print(f"MLX Whisper sidecar listening on {socket_path}", file=sys.stderr)

    while True:
        conn, _ = sock.accept()
        try:
            handle_connection(conn, model_name)
        except Exception as e:
            print(f"Connection error: {e}", file=sys.stderr)
        finally:
            conn.close()


def handle_connection(conn, model_name):
    buf = b""
    while True:
        data = conn.recv(4096)
        if not data:
            break
        buf += data
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            wav_path = line.decode("utf-8").strip()
            if not wav_path:
                continue

            try:
                result = mlx_whisper.transcribe(
                    wav_path,
                    path_or_hf_repo=model_name,
                    language="en",
                )
                text = result.get("text", "").strip()
                response = json.dumps({"text": text, "confidence": 0.9})
            except Exception as e:
                response = json.dumps({"text": "", "confidence": 0.0, "error": str(e)})

            conn.sendall((response + "\n").encode("utf-8"))


if __name__ == "__main__":
    main()
```

Create `Scripts/mlx-whisper-sidecar/README.md`:

```markdown
# MLX Whisper Sidecar

## Requirements

- Python 3.10+
- Apple Silicon Mac

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Test manually

```bash
export VOXOPS_SOCKET=/tmp/voxops-mlx.sock
python3 server.py &
echo "/path/to/test.wav" | socat - UNIX-CONNECT:/tmp/voxops-mlx.sock
```
```

- [ ] **Step 2: Implement MLXWhisperBackend**

Create `Sources/VoxOpsCore/STT/MLXWhisperBackend.swift`:

```swift
import Foundation

/// MLX Whisper sidecar backend.
/// Spawns a Python Unix socket server, sends WAV paths, receives JSON transcripts.
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
        lock.lock()
        defer { lock.unlock() }
        return _status
    }

    public init(
        scriptPath: String,
        pythonPath: String = "/usr/bin/python3",
        modelName: String = "mlx-community/whisper-small-mlx"
    ) {
        self.scriptPath = scriptPath
        self.pythonPath = pythonPath
        self.modelName = modelName
    }

    public func start() async throws {
        lock.lock()
        defer { lock.unlock() }

        _status = .starting

        let sockPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxops-mlx-\(ProcessInfo.processInfo.processIdentifier).sock")
            .path
        self.socketPath = sockPath

        let proc = SidecarProcess(
            executablePath: pythonPath,
            arguments: [scriptPath],
            environment: [
                "VOXOPS_SOCKET": sockPath,
                "WHISPER_MODEL": modelName
            ]
        )
        try proc.start()
        sidecar = proc

        // Wait for socket to appear (server startup)
        for _ in 0..<50 { // 5 seconds max
            if FileManager.default.fileExists(atPath: sockPath) {
                _status = .ready
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        _status = .error("Socket did not appear after 5s")
        throw SidecarError.timeout
    }

    public func stop() async {
        lock.lock()
        defer { lock.unlock() }

        sidecar?.stop()
        sidecar = nil
        if let sock = socketPath {
            try? FileManager.default.removeItem(atPath: sock)
        }
        socketPath = nil
        _status = .idle
    }

    public func transcribe(audio: AudioBuffer) async throws -> TranscriptResult {
        lock.lock()
        if sidecar == nil || !(sidecar?.isRunning ?? false) {
            lock.unlock()
            try await start()
        } else {
            lock.unlock()
        }

        lock.lock()
        _status = .transcribing
        guard let sockPath = socketPath else {
            _status = .error("No socket path")
            lock.unlock()
            throw SidecarError.notRunning
        }
        lock.unlock()

        let startTime = CFAbsoluteTimeGetCurrent()

        // Write audio to temp WAV file
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxops-\(UUID().uuidString).wav")
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
                        let bound = ptr.withMemoryRebound(to: CChar.self, capacity: Int(104)) { $0 }
                        for (i, byte) in pathBytes.enumerated() where i < 104 {
                            bound[i] = byte
                        }
                    }

                    let addrLen = socklen_t(MemoryLayout.offset(of: \sockaddr_un.sun_path)! + sockPath.utf8.count + 1)
                    let connectResult = withUnsafePointer(to: &addr) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            connect(fd, $0, addrLen)
                        }
                    }
                    guard connectResult == 0 else { throw SidecarError.notRunning }

                    // Send wav path
                    let message = tempFile.path + "\n"
                    message.utf8CString.withUnsafeBufferPointer { buf in
                        _ = write(fd, buf.baseAddress!, message.utf8.count)
                    }

                    // Read response
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
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        guard let jsonData = jsonLine.data(using: .utf8) else {
            lock.lock()
            _status = .error("Invalid response encoding")
            lock.unlock()
            throw SidecarError.encodingFailed
        }

        let decoded = try JSONDecoder().decode(TranscriptJSON.self, from: jsonData)

        lock.lock()
        _status = .ready
        lock.unlock()

        return TranscriptResult(
            text: decoded.text,
            confidence: decoded.confidence ?? 0.9,
            latencyMs: Int(elapsed * 1000),
            backend: id
        )
    }
}
```

- [ ] **Step 3: Run all tests**

Run: `swift test`
Expected: All PASS (MLXWhisperBackend doesn't have unit tests — it requires the Python sidecar running. Tested via integration.)

- [ ] **Step 4: Commit**

```bash
git add Sources/VoxOpsCore/STT/MLXWhisperBackend.swift Scripts/mlx-whisper-sidecar/
git commit -m "feat: add MLX Whisper STT backend with Unix socket sidecar"
```

---

## Task 8: Raw Text Formatter

**Files:**
- Create: `Sources/VoxOpsCore/Pipeline/RawFormatter.swift`
- Create: `Tests/VoxOpsCoreTests/RawFormatterTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/VoxOpsCoreTests/RawFormatterTests.swift`:

```swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("RawFormatter")
struct RawFormatterTests {
    let formatter = RawFormatter()

    @Test("capitalizes first letter of sentence")
    func capitalizesFirst() {
        #expect(formatter.format("hello world") == "Hello world")
    }

    @Test("preserves already capitalized text")
    func preservesCapitalized() {
        #expect(formatter.format("Hello world") == "Hello world")
    }

    @Test("trims whitespace")
    func trimsWhitespace() {
        #expect(formatter.format("  hello world  ") == "Hello world")
    }

    @Test("handles empty string")
    func handlesEmpty() {
        #expect(formatter.format("") == "")
    }

    @Test("adds period at end if no terminal punctuation")
    func addsPeriod() {
        #expect(formatter.format("hello world") == "Hello world")
    }

    @Test("preserves existing terminal punctuation")
    func preservesPunctuation() {
        #expect(formatter.format("is this working?") == "Is this working?")
        #expect(formatter.format("wow!") == "Wow!")
    }

    @Test("collapses multiple spaces")
    func collapsesSpaces() {
        #expect(formatter.format("hello   world") == "Hello world")
    }

    @Test("handles multiple sentences")
    func multipleSentences() {
        let result = formatter.format("hello world. this is a test")
        #expect(result == "Hello world. This is a test")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RawFormatterTests`
Expected: FAIL — `RawFormatter` not found

- [ ] **Step 3: Implement RawFormatter**

Create `Sources/VoxOpsCore/Pipeline/RawFormatter.swift`:

```swift
import Foundation

/// Minimal text cleanup for Raw mode.
/// Capitalizes sentence starts, collapses spaces, trims whitespace.
/// Does NOT add periods — raw mode should feel like dictation, not prose.
public struct RawFormatter: Sendable {

    public init() {}

    public func format(_ text: String) -> String {
        var result = text
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if result.isEmpty { return result }

        // Collapse multiple spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        // Capitalize sentence starts
        result = capitalizeSentences(result)

        return result
    }

    private func capitalizeSentences(_ text: String) -> String {
        var result = ""
        var capitalizeNext = true

        for char in text {
            if capitalizeNext && char.isLetter {
                result.append(char.uppercased())
                capitalizeNext = false
            } else {
                result.append(char)
            }

            if char == "." || char == "!" || char == "?" {
                capitalizeNext = true
            }
        }

        return result
    }
}
```

- [ ] **Step 4: Run tests — expect some to fail, adjust**

Run: `swift test --filter RawFormatterTests`

The "adds period" test expects a period but RawFormatter doesn't add periods (raw mode). Update the test:

```swift
    @Test("does not add period in raw mode")
    func noPeriodAdded() {
        #expect(formatter.format("hello world") == "Hello world")
    }
```

- [ ] **Step 5: Run tests again**

Run: `swift test --filter RawFormatterTests`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/VoxOpsCore/Pipeline/ Tests/VoxOpsCoreTests/RawFormatterTests.swift
git commit -m "feat: add RawFormatter for minimal transcript cleanup"
```

---

## Task 9: Text Injection Layer

**Files:**
- Create: `Sources/VoxOpsCore/Injection/TextInjector.swift`
- Create: `Sources/VoxOpsCore/Injection/AccessibilityInjector.swift`
- Create: `Sources/VoxOpsCore/Injection/ClipboardInjector.swift`
- Create: `Tests/VoxOpsCoreTests/ClipboardInjectorTests.swift`

- [ ] **Step 1: Write failing test for ClipboardInjector**

Create `Tests/VoxOpsCoreTests/ClipboardInjectorTests.swift`:

```swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("ClipboardInjector")
struct ClipboardInjectorTests {
    @Test("buildPasteScript returns valid AppleScript")
    func buildScript() {
        let script = ClipboardInjector.buildPasteScript(text: "hello")
        #expect(script.contains("set the clipboard to"))
        #expect(script.contains("hello"))
        #expect(script.contains("keystroke \"v\""))
    }

    @Test("escapes quotes in text")
    func escapesQuotes() {
        let script = ClipboardInjector.buildPasteScript(text: "say \"hello\"")
        #expect(script.contains("say \\\"hello\\\""))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClipboardInjectorTests`
Expected: FAIL — types not found

- [ ] **Step 3: Implement TextInjector protocol**

Create `Sources/VoxOpsCore/Injection/TextInjector.swift`:

```swift
import Foundation

/// Strategy for injecting text into the active app
public enum InjectionStrategy: String, Sendable {
    case accessibility  // AXUIElement
    case clipboard      // Cmd+V with clipboard save/restore
    case auto           // try accessibility, fall back to clipboard
}

/// Result of a text injection attempt
public struct InjectionResult: Sendable {
    public let success: Bool
    public let strategy: InjectionStrategy
    public let error: String?

    public init(success: Bool, strategy: InjectionStrategy, error: String? = nil) {
        self.success = success
        self.strategy = strategy
        self.error = error
    }
}

/// Coordinates text injection: tries Accessibility API first, falls back to clipboard.
public final class TextInjector: Sendable {
    private let accessibilityInjector: AccessibilityInjector
    private let clipboardInjector: ClipboardInjector

    public init() {
        self.accessibilityInjector = AccessibilityInjector()
        self.clipboardInjector = ClipboardInjector()
    }

    public func inject(text: String, strategy: InjectionStrategy = .auto) async -> InjectionResult {
        switch strategy {
        case .accessibility:
            return await accessibilityInjector.inject(text: text)
        case .clipboard:
            return await clipboardInjector.inject(text: text)
        case .auto:
            let axResult = await accessibilityInjector.inject(text: text)
            if axResult.success { return axResult }
            return await clipboardInjector.inject(text: text)
        }
    }
}
```

- [ ] **Step 4: Implement AccessibilityInjector**

Create `Sources/VoxOpsCore/Injection/AccessibilityInjector.swift`:

```swift
import Foundation
import ApplicationServices

/// Injects text via macOS Accessibility API (AXUIElement).
/// Requires Accessibility permission in System Settings.
public final class AccessibilityInjector: Sendable {

    public init() {}

    public func inject(text: String) async -> InjectionResult {
        // Check if we have Accessibility permission
        guard AXIsProcessTrusted() else {
            return InjectionResult(
                success: false,
                strategy: .accessibility,
                error: "Accessibility permission not granted"
            )
        }

        // Get the focused application
        guard let focusedApp = NSWorkspace.shared.frontmostApplication else {
            return InjectionResult(
                success: false,
                strategy: .accessibility,
                error: "No frontmost application"
            )
        }

        let appElement = AXUIElementCreateApplication(focusedApp.processIdentifier)

        // Get focused UI element
        var focusedElement: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard focusErr == .success, let element = focusedElement else {
            return InjectionResult(
                success: false,
                strategy: .accessibility,
                error: "Cannot get focused element (error: \(focusErr.rawValue))"
            )
        }

        let axElement = element as! AXUIElement

        // Try to get selected text range and insert at cursor
        var selectedRange: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRange)

        if rangeErr == .success {
            // Has selected text range — use AXSelectedText to insert
            let setErr = AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            if setErr == .success {
                return InjectionResult(success: true, strategy: .accessibility)
            }
        }

        // Fallback: try setting AXValue directly (replaces entire field)
        var currentValue: CFTypeRef?
        let valErr = AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &currentValue)
        if valErr == .success, let current = currentValue as? String {
            let newValue = current + text
            let setErr = AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, newValue as CFTypeRef)
            if setErr == .success {
                return InjectionResult(success: true, strategy: .accessibility)
            }
        }

        return InjectionResult(
            success: false,
            strategy: .accessibility,
            error: "Could not set text via AX API"
        )
    }
}
```

- [ ] **Step 5: Implement ClipboardInjector**

Create `Sources/VoxOpsCore/Injection/ClipboardInjector.swift`:

```swift
import Foundation
import AppKit
import CoreGraphics

/// Injects text via clipboard: save → set → Cmd+V → restore.
/// Universal fallback when Accessibility API fails.
public final class ClipboardInjector: Sendable {

    public init() {}

    public func inject(text: String) async -> InjectionResult {
        let pasteboard = NSPasteboard.general

        // Save current clipboard
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> (String, Data)? in
            guard let type = item.types.first,
                  let data = item.data(forType: type) else { return nil }
            return (type.rawValue, data)
        } ?? []

        // Set our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        simulatePaste()

        // Wait briefly for paste to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Restore clipboard
        pasteboard.clearContents()
        for (typeRaw, data) in savedItems {
            let type = NSPasteboard.PasteboardType(typeRaw)
            pasteboard.setData(data, forType: type)
        }

        return InjectionResult(success: true, strategy: .clipboard)
    }

    private func simulatePaste() {
        // Cmd+V keydown
        let vKeyCode: CGKeyCode = 0x09
        if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
    }

    /// Build AppleScript for paste (alternative method, exposed for testing)
    public static func buildPasteScript(text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        set the clipboard to "\(escaped)"
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
    }
}
```

- [ ] **Step 6: Run tests**

Run: `swift test --filter ClipboardInjectorTests`
Expected: All PASS

- [ ] **Step 7: Run all tests**

Run: `swift test`
Expected: All PASS

- [ ] **Step 8: Commit**

```bash
git add Sources/VoxOpsCore/Injection/ Tests/VoxOpsCoreTests/ClipboardInjectorTests.swift
git commit -m "feat: add text injection layer with AX API and clipboard fallback"
```

---

## Task 10: Hotkey Manager

**Files:**
- Create: `Sources/VoxOpsCore/Hotkey/HotkeyManager.swift`

- [ ] **Step 1: Implement HotkeyManager**

Note: CGEvent taps require Accessibility permission and cannot be meaningfully unit-tested. This component is tested via manual integration testing.

Create `Sources/VoxOpsCore/Hotkey/HotkeyManager.swift`:

```swift
import Foundation
import CoreGraphics

/// Captures global push-to-talk hotkey via CGEvent tap.
/// Fires callbacks on key down (start recording) and key up (stop recording).
public final class HotkeyManager: @unchecked Sendable {
    public typealias KeyHandler = @Sendable () -> Void

    private let keyCode: CGKeyCode
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let lock = NSLock()

    public var onKeyDown: KeyHandler?
    public var onKeyUp: KeyHandler?

    /// Initialize with a virtual key code. Default 0x31 = Space.
    /// Common choices: 0x31 (Space), 0x3A (Option), 0x38 (Shift)
    public init(keyCode: CGKeyCode = 0x31) {
        self.keyCode = keyCode
    }

    /// Start listening for global hotkey events.
    /// Requires Accessibility permission.
    public func start() throws {
        lock.lock()
        defer { lock.unlock() }

        guard AXIsProcessTrusted() else {
            throw HotkeyError.accessibilityNotGranted
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        // Use Unmanaged to pass self to the C callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            throw HotkeyError.cannotCreateEventTap
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Stop listening for hotkey events
    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        guard eventKeyCode == keyCode else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            // Suppress repeat events (key held down)
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                onKeyDown?()
            }
            // Consume the event so it doesn't reach the active app
            return nil
        case .keyUp:
            onKeyUp?()
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

public enum HotkeyError: Error, Sendable {
    case accessibilityNotGranted
    case cannotCreateEventTap
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/VoxOpsCore/Hotkey/
git commit -m "feat: add HotkeyManager with CGEvent tap for push-to-talk"
```

---

## Task 11: HUD Orb Window

**Files:**
- Create: `VoxOpsApp/Views/HUDWindow.swift`
- Create: `VoxOpsApp/Views/HUDOrbView.swift`

- [ ] **Step 1: Define VoxOps state enum in core**

Add to a new file `Sources/VoxOpsCore/Pipeline/VoxState.swift`:

```swift
import Foundation

/// Current state of the VoxOps pipeline, drives HUD visualization
public enum VoxState: Sendable, Equatable {
    case idle
    case listening
    case processing
    case success
    case error(String)
}
```

- [ ] **Step 2: Implement HUDWindow**

Create `VoxOpsApp/Views/HUDWindow.swift`:

```swift
import AppKit
import SwiftUI

/// Non-activating floating panel for the VoxOps orb.
/// Never steals focus from the active app.
final class HUDWindow: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 48, height: 48),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.contentView = contentView
        self.isFloatingPanel = true
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false

        // Position in bottom-right of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 64
            let y = screenFrame.minY + 16
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}
```

- [ ] **Step 3: Implement HUDOrbView**

Create `VoxOpsApp/Views/HUDOrbView.swift`:

```swift
import SwiftUI

struct HUDOrbView: View {
    let state: VoxState

    @State private var isPulsing = false
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .fill(orbColor)
            .frame(width: 32, height: 32)
            .shadow(color: glowColor, radius: glowRadius)
            .scaleEffect(isPulsing ? 1.15 : 1.0)
            .rotationEffect(.degrees(isProcessing ? rotation : 0))
            .overlay(processingRing)
            .onChange(of: state) { _, newState in
                updateAnimations(newState)
            }
            .onAppear {
                updateAnimations(state)
            }
    }

    private var orbColor: Color {
        switch state {
        case .idle: return Color(white: 0.3)
        case .listening: return Color.red
        case .processing: return Color.orange
        case .success: return Color.green
        case .error: return Color.red
        }
    }

    private var glowColor: Color {
        switch state {
        case .idle: return .clear
        case .listening: return Color.red.opacity(0.6)
        case .processing: return Color.orange.opacity(0.5)
        case .success: return Color.green.opacity(0.5)
        case .error: return Color.red.opacity(0.5)
        }
    }

    private var glowRadius: CGFloat {
        state == .idle ? 0 : 12
    }

    private var isProcessing: Bool {
        if case .processing = state { return true }
        return false
    }

    @ViewBuilder
    private var processingRing: some View {
        if isProcessing {
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(Color.orange, lineWidth: 2)
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(rotation))
        }
    }

    private func updateAnimations(_ newState: VoxState) {
        switch newState {
        case .listening:
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        case .processing:
            isPulsing = false
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        case .success:
            isPulsing = false
            rotation = 0
            // Flash green then fade to idle after 1s
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Parent should set state back to idle
            }
        case .error:
            isPulsing = false
            rotation = 0
        case .idle:
            withAnimation {
                isPulsing = false
                rotation = 0
            }
        }
    }
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `swift build` (core library)

Note: The SwiftUI views in VoxOpsApp are compiled via Xcode, not SPM. Verify they have no syntax errors by inspection. Full build verification happens in Task 13 when the Xcode project is created.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoxOpsCore/Pipeline/VoxState.swift VoxOpsApp/Views/HUDWindow.swift VoxOpsApp/Views/HUDOrbView.swift
git commit -m "feat: add HUD floating orb with state-driven animations"
```

---

## Task 12: Menu Bar and Settings Views

**Files:**
- Create: `VoxOpsApp/Views/MenuBarView.swift`
- Create: `VoxOpsApp/Views/SettingsView.swift`
- Create: `VoxOpsApp/AppState.swift`

- [ ] **Step 1: Implement AppState**

Create `VoxOpsApp/AppState.swift`:

```swift
import Foundation
import SwiftUI
import VoxOpsCore

/// Central app state. Orchestrates the full pipeline:
/// hotkey → audio → STT → formatter → injection
@MainActor
final class AppState: ObservableObject {
    @Published var voxState: VoxState = .idle
    @Published var lastTranscript: String = ""
    @Published var selectedBackend: String = "whisper.cpp"
    @Published var isSettingsOpen = false

    private var database: Database?
    private var settingsStore: SettingsStore?
    private var audioManager: AudioManager?
    private var hotkeyManager: HotkeyManager?
    private var textInjector: TextInjector?
    private var rawFormatter: RawFormatter?
    private var activeBackend: (any STTBackend)?

    func setup() {
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("VoxOps")
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

            let db = try Database(directory: appSupport)
            self.database = db
            self.settingsStore = SettingsStore(database: db)
            self.audioManager = AudioManager()
            self.textInjector = TextInjector()
            self.rawFormatter = RawFormatter()

            setupHotkey()
        } catch {
            voxState = .error("Setup failed: \(error.localizedDescription)")
        }
    }

    private func setupHotkey() {
        // Default hotkey: Right Option (keyCode 0x3D)
        // TODO: Make configurable via settings
        let hk = HotkeyManager(keyCode: 0x3D)
        hk.onKeyDown = { [weak self] in
            Task { @MainActor in
                self?.startListening()
            }
        }
        hk.onKeyUp = { [weak self] in
            Task { @MainActor in
                self?.stopListeningAndProcess()
            }
        }
        do {
            try hk.start()
            self.hotkeyManager = hk
        } catch {
            voxState = .error("Hotkey setup failed: \(error.localizedDescription)")
        }
    }

    private func startListening() {
        voxState = .listening
        do {
            try audioManager?.startRecording()
        } catch {
            voxState = .error("Recording failed: \(error.localizedDescription)")
        }
    }

    private func stopListeningAndProcess() {
        guard let audioManager else { return }
        let audio = audioManager.stopRecording()

        guard audio.duration > 0.1 else {
            voxState = .idle
            return
        }

        voxState = .processing

        Task {
            do {
                // Ensure backend is started
                if activeBackend == nil {
                    activeBackend = createBackend()
                }
                guard let backend = activeBackend else {
                    voxState = .error("No STT backend configured")
                    return
                }

                let result = try await backend.transcribe(audio: audio)
                let formatted = rawFormatter?.format(result.text) ?? result.text
                lastTranscript = formatted

                // Inject text
                if let injector = textInjector {
                    let injResult = await injector.inject(text: formatted)
                    if injResult.success {
                        voxState = .success
                    } else {
                        voxState = .error("Injection failed: \(injResult.error ?? "unknown")")
                    }
                }

                // Return to idle after success flash
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if case .success = voxState {
                    voxState = .idle
                }
            } catch {
                voxState = .error("STT failed: \(error.localizedDescription)")
            }
        }
    }

    private func createBackend() -> (any STTBackend)? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VoxOps")

        switch selectedBackend {
        case "whisper.cpp":
            // Find the sidecar script relative to app bundle or Scripts/
            let scriptPath = Bundle.main.path(forResource: "run", ofType: "sh", inDirectory: "whisper-sidecar")
                ?? "Scripts/whisper-sidecar/run.sh"
            let modelPath = appSupport.appendingPathComponent("Models/ggml-small.bin").path
            return WhisperCppBackend(scriptPath: scriptPath, modelPath: modelPath)

        case "mlx-whisper":
            let scriptPath = Bundle.main.path(forResource: "server", ofType: "py", inDirectory: "mlx-whisper-sidecar")
                ?? "Scripts/mlx-whisper-sidecar/server.py"
            return MLXWhisperBackend(scriptPath: scriptPath)

        default:
            return nil
        }
    }
}
```

- [ ] **Step 2: Implement MenuBarView**

Create `VoxOpsApp/Views/MenuBarView.swift`:

```swift
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text("VoxOps")
                    .font(.headline)
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Mode: Raw")
                    Spacer()
                    Text("⌘1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Backend: \(appState.selectedBackend)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if !appState.lastTranscript.isEmpty {
                Divider()
                Text(appState.lastTranscript)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }

            Divider()

            Button("Settings...") {
                appState.isSettingsOpen = true
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            Button("Quit VoxOps") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 240)
    }

    private var statusColor: Color {
        switch appState.voxState {
        case .idle: return .green
        case .listening: return .red
        case .processing: return .orange
        case .success: return .green
        case .error: return .red
        }
    }

    private var statusText: String {
        switch appState.voxState {
        case .idle: return "Ready"
        case .listening: return "Listening..."
        case .processing: return "Processing..."
        case .success: return "Done"
        case .error(let msg): return msg
        }
    }
}
```

- [ ] **Step 3: Implement basic SettingsView**

Create `VoxOpsApp/Views/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selectedBackend = "whisper.cpp"

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            audioTab
                .tabItem { Label("Audio", systemImage: "mic") }
        }
        .frame(width: 450, height: 300)
        .onAppear {
            selectedBackend = appState.selectedBackend
        }
    }

    private var generalTab: some View {
        Form {
            Section("Hotkey") {
                Text("Push-to-talk: Right Option (⌥)")
                    .foregroundStyle(.secondary)
                Text("Hotkey customization coming in a future update.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("STT Backend") {
                Picker("Backend", selection: $selectedBackend) {
                    Text("whisper.cpp").tag("whisper.cpp")
                    Text("MLX Whisper").tag("mlx-whisper")
                }
                .onChange(of: selectedBackend) { _, newValue in
                    appState.selectedBackend = newValue
                }
            }
        }
        .padding()
    }

    private var audioTab: some View {
        Form {
            Section("Microphone") {
                Text("Using system default microphone")
                    .foregroundStyle(.secondary)
                Text("Microphone selection coming in a future update.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }
}
```

- [ ] **Step 4: Build core library**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add VoxOpsApp/AppState.swift VoxOpsApp/Views/MenuBarView.swift VoxOpsApp/Views/SettingsView.swift
git commit -m "feat: add AppState orchestrator, menu bar view, and settings UI"
```

---

## Task 13: Wire Up the App Entry Point

**Files:**
- Modify: `VoxOpsApp/VoxOpsApp.swift`

- [ ] **Step 1: Update VoxOpsApp.swift to wire everything together**

Replace `VoxOpsApp/VoxOpsApp.swift`:

```swift
import SwiftUI
import VoxOpsCore

@main
struct VoxOpsApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        // Settings window
        Settings {
            SettingsView(appState: appState)
        }
    }

    private var menuBarIcon: String {
        switch appState.voxState {
        case .idle: return "waveform.circle"
        case .listening: return "waveform.circle.fill"
        case .processing: return "arrow.triangle.2.circlepath.circle"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    init() {
        // Setup happens in AppState.setup() called from onAppear
        // to ensure we're on the main thread
    }
}
```

Note: `appState.setup()` should be called on app launch. Add an `.onAppear` or use an `NSApplicationDelegateAdaptor` — but since `MenuBarExtra` doesn't have `.onAppear`, we use a delegate:

Add to `VoxOpsApp/VoxOpsApp.swift` (inside the struct, before `var body`):

```swift
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    class AppDelegate: NSObject, NSApplicationDelegate {
        var appState: AppState?

        func applicationDidFinishLaunching(_ notification: Notification) {
            // AppState setup is triggered separately
        }
    }
```

Actually, simpler approach — call setup in the StateObject's init. Update AppState:

Add to the top of `AppState.swift`:

```swift
    init() {
        // Defer setup to after SwiftUI has initialized
        DispatchQueue.main.async { [weak self] in
            self?.setup()
        }
    }
```

- [ ] **Step 2: Create entitlements file**

Create `VoxOpsApp/VoxOpsApp.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

Note: We disable sandboxing because we need CGEvent tap (global hotkey), Accessibility API access, and sidecar process spawning. These require running outside the sandbox. Microphone permission is still requested.

- [ ] **Step 3: Create Info.plist for the app**

Create `VoxOpsApp/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoxOps needs microphone access for push-to-talk voice input.</string>
    <key>CFBundleName</key>
    <string>VoxOps</string>
    <key>CFBundleIdentifier</key>
    <string>com.voxops.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
</dict>
</plist>
```

`LSUIElement = true` makes it a menu bar-only app (no Dock icon).

- [ ] **Step 4: Build core library**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add VoxOpsApp/VoxOpsApp.swift VoxOpsApp/VoxOpsApp.entitlements VoxOpsApp/Info.plist
git commit -m "feat: wire up app entry point with MenuBarExtra, delegate, and entitlements"
```

---

## Task 14: Xcode Project Generation

**Files:**
- Create: `project.yml` (for xcodegen)

- [ ] **Step 1: Create xcodegen project spec**

We use [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from a YAML spec. This avoids checking in `.xcodeproj` files.

Create `project.yml`:

```yaml
name: VoxOps
options:
  bundleIdPrefix: com.voxops
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "15.0"

packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift.git
    from: "7.0.0"

targets:
  VoxOpsCore:
    type: framework
    platform: macOS
    sources:
      - Sources/VoxOpsCore
    dependencies:
      - package: GRDB
    settings:
      SWIFT_VERSION: "5.9"

  VoxOpsApp:
    type: application
    platform: macOS
    sources:
      - VoxOpsApp
    dependencies:
      - target: VoxOpsCore
    settings:
      SWIFT_VERSION: "5.9"
      INFOPLIST_FILE: VoxOpsApp/Info.plist
      CODE_SIGN_ENTITLEMENTS: VoxOpsApp/VoxOpsApp.entitlements
      PRODUCT_BUNDLE_IDENTIFIER: com.voxops.app
      LS_UI_ELEMENT: true
    resources:
      - Scripts/whisper-sidecar
      - Scripts/mlx-whisper-sidecar

  VoxOpsCoreTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests/VoxOpsCoreTests
    dependencies:
      - target: VoxOpsCore
    settings:
      SWIFT_VERSION: "5.9"
```

- [ ] **Step 2: Generate Xcode project**

Run: `which xcodegen || brew install xcodegen`
Run: `xcodegen generate`
Expected: `VoxOps.xcodeproj` is created

- [ ] **Step 3: Build via xcodebuild**

Run: `xcodebuild -project VoxOps.xcodeproj -scheme VoxOpsApp -configuration Debug build`
Expected: Build succeeds

- [ ] **Step 4: Run tests via xcodebuild**

Run: `xcodebuild -project VoxOps.xcodeproj -scheme VoxOpsCoreTests -configuration Debug test`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add project.yml
git commit -m "feat: add XcodeGen project spec for building VoxOps.app"
```

---

## Task 15: Integration Test — Full Pipeline

**Files:**
- Create: `Tests/VoxOpsCoreTests/PipelineIntegrationTests.swift`

- [ ] **Step 1: Write integration test for the pipeline (mocked STT)**

Create `Tests/VoxOpsCoreTests/PipelineIntegrationTests.swift`:

```swift
import Testing
import Foundation
@testable import VoxOpsCore

/// Mock STT backend for integration testing without a real model
final class MockSTTBackend: STTBackend, @unchecked Sendable {
    let id = "mock"
    var status: BackendStatus = .ready
    var transcriptToReturn = "hello world"

    func start() async throws { status = .ready }
    func stop() async { status = .idle }

    func transcribe(audio: AudioBuffer) async throws -> TranscriptResult {
        return TranscriptResult(
            text: transcriptToReturn,
            confidence: 0.95,
            latencyMs: 10,
            backend: id
        )
    }
}

@Suite("Pipeline Integration")
struct PipelineIntegrationTests {
    @Test("audio buffer through STT and formatter produces clean text")
    func fullPipeline() async throws {
        // 1. Create audio buffer (simulated)
        let audio = AudioBuffer(pcmData: Data(repeating: 0, count: 32000))

        // 2. Transcribe via mock backend
        let backend = MockSTTBackend()
        backend.transcriptToReturn = "  hello world  this is a test  "
        let transcript = try await backend.transcribe(audio: audio)

        // 3. Format with RawFormatter
        let formatter = RawFormatter()
        let formatted = formatter.format(transcript.text)

        #expect(formatted == "Hello world this is a test")
    }

    @Test("WAV round-trip produces valid file")
    func wavRoundTrip() throws {
        let original = Data(repeating: 42, count: 16000)
        let buffer = AudioBuffer(pcmData: original)

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        try buffer.writeWAV(to: tempFile)

        let written = try Data(contentsOf: tempFile)
        // 44 byte WAV header + 16000 bytes data
        #expect(written.count == 16044)

        // Verify we can read back the PCM data
        let pcmData = written.subdata(in: 44..<written.count)
        #expect(pcmData == original)
    }
}
```

- [ ] **Step 2: Run integration tests**

Run: `swift test --filter PipelineIntegrationTests`
Expected: All PASS

- [ ] **Step 3: Run full test suite**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add Tests/VoxOpsCoreTests/PipelineIntegrationTests.swift
git commit -m "test: add pipeline integration tests with mock STT backend"
```

---

## Summary

| Task | Component | Tests |
|------|-----------|-------|
| 1 | Project scaffold | build verification |
| 2 | SQLite + SettingsStore | DatabaseTests, SettingsStoreTests |
| 3 | AudioBuffer + AudioManager | AudioBufferTests |
| 4 | SidecarProcess | SidecarProcessTests |
| 5 | STTBackend protocol + TranscriptResult | TranscriptResultTests |
| 6 | whisper.cpp backend + sidecar script | WhisperCppBackendTests |
| 7 | MLX Whisper backend + sidecar server | — (integration only) |
| 8 | RawFormatter | RawFormatterTests |
| 9 | Text injection (AX + clipboard) | ClipboardInjectorTests |
| 10 | HotkeyManager | — (requires permissions) |
| 11 | HUD orb window + animations | — (visual verification) |
| 12 | Menu bar, settings, AppState | — (UI verification) |
| 13 | App entry point wiring | — (build verification) |
| 14 | Xcode project generation | xcodebuild test |
| 15 | Pipeline integration test | PipelineIntegrationTests |

After completing all 15 tasks, you will have a working V1 that:
- Launches as a menu bar app
- Shows a floating HUD orb
- Captures global push-to-talk hotkey
- Records microphone audio
- Transcribes via whisper.cpp or MLX Whisper
- Applies minimal text cleanup
- Injects text at the cursor via Accessibility API (with clipboard fallback)
- Persists settings in SQLite
