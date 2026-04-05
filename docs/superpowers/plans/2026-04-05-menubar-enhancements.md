# Menu Bar Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add five features to the menu bar dropdown — STT backend picker, mic selector, transcription history, formatting modes, and usage stats — organized in a tabbed Main/Stats interface.

**Architecture:** Thin dropdown, fat core. All business logic lives in VoxOpsCore (TranscriptionHistory, FormatterRegistry, AudioDeviceManager) with SQLite persistence via GRDB. The dropdown is pure SwiftUI binding to AppState published properties. AppState coordinates but holds no business logic.

**Tech Stack:** Swift 5.9, SwiftUI, GRDB (SQLite), CoreAudio C API, AVFoundation, Swift Testing framework

**Spec:** `docs/superpowers/specs/2026-04-05-menubar-enhancements-design.md`

---

### Task 1: TranscriptionHistory — Database Migration and Model

**Files:**
- Modify: `Sources/VoxOpsCore/Storage/Database.swift:60-68` (add migration)
- Create: `Sources/VoxOpsCore/Storage/TranscriptionHistory.swift`
- Test: `Tests/VoxOpsCoreTests/TranscriptionHistoryTests.swift`

- [ ] **Step 1: Write failing test — migration creates transcriptions table**

```swift
// Tests/VoxOpsCoreTests/TranscriptionHistoryTests.swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("TranscriptionHistory")
struct TranscriptionHistoryTests {
    @Test("migration creates transcriptions table")
    func migrationCreatesTable() throws {
        let db = try Database(inMemory: true)
        let version = try db.schemaVersion()
        #expect(version >= 2) // v1_settings + v2_transcriptions (at minimum)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TranscriptionHistoryTests 2>&1 | tail -10`
Expected: FAIL — version is 1, not 2

- [ ] **Step 3: Add migration in Database.swift**

Add after the `v1_settings` migration in `registerMigrations(on:)` (line 67):

```swift
migrator.registerMigration("v2_transcriptions") { db in
    try db.create(table: "transcriptions") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("text", .text).notNull()
        t.column("duration_ms", .integer).notNull()
        t.column("latency_ms", .integer).notNull()
        t.column("created_at", .text).notNull().defaults(sql: "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TranscriptionHistoryTests 2>&1 | tail -10`
Expected: PASS

- [ ] **Step 5: Run full test suite to verify no regressions**

Run: `swift test 2>&1 | tail -5`
Expected: All tests pass (the DatabaseTests.createDatabase test should now report version 2)

- [ ] **Step 6: Commit**

```bash
git add Sources/VoxOpsCore/Storage/Database.swift Tests/VoxOpsCoreTests/TranscriptionHistoryTests.swift
git commit -m "feat: add transcriptions table migration"
```

---

### Task 2: TranscriptionHistory — Record and Recent

**Files:**
- Create: `Sources/VoxOpsCore/Storage/TranscriptionHistory.swift`
- Test: `Tests/VoxOpsCoreTests/TranscriptionHistoryTests.swift` (add tests)

- [ ] **Step 1: Write failing tests — record and recent**

Add to `TranscriptionHistoryTests.swift`:

```swift
@Test("record and recent returns entries in reverse chronological order")
func recordAndRecent() throws {
    let db = try Database(inMemory: true)
    let history = TranscriptionHistory(database: db)
    try history.record(text: "first", durationMs: 1000, latencyMs: 200)
    try history.record(text: "second", durationMs: 2000, latencyMs: 300)
    let entries = try history.recent(limit: 5)
    #expect(entries.count == 2)
    #expect(entries[0].text == "second") // newest first
    #expect(entries[1].text == "first")
    #expect(entries[0].durationMs == 2000)
    #expect(entries[0].latencyMs == 300)
}

@Test("recent respects limit")
func recentLimit() throws {
    let db = try Database(inMemory: true)
    let history = TranscriptionHistory(database: db)
    for i in 1...10 {
        try history.record(text: "entry \(i)", durationMs: 100, latencyMs: 50)
    }
    let entries = try history.recent(limit: 3)
    #expect(entries.count == 3)
    #expect(entries[0].text == "entry 10")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TranscriptionHistoryTests 2>&1 | tail -10`
Expected: FAIL — TranscriptionHistory not defined

- [ ] **Step 3: Implement TranscriptionHistory with record and recent**

```swift
// Sources/VoxOpsCore/Storage/TranscriptionHistory.swift
import Foundation
import GRDB

public struct TranscriptionEntry: Sendable, Codable, FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "transcriptions"
    public var id: Int64?
    public let text: String
    public let durationMs: Int
    public let latencyMs: Int
    public let createdAt: String // Stored as ISO 8601 TEXT, decoded as String to avoid date parsing issues

    enum CodingKeys: String, CodingKey {
        case id, text
        case durationMs = "duration_ms"
        case latencyMs = "latency_ms"
        case createdAt = "created_at"
    }

    public init(text: String, durationMs: Int, latencyMs: Int) {
        self.id = nil
        self.text = text
        self.durationMs = durationMs
        self.latencyMs = latencyMs
        // ISO 8601 UTC timestamp
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.createdAt = formatter.string(from: Date())
    }

    /// Parse createdAt string back to Date for display
    public var date: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAt) ?? Date()
    }
}

public final class TranscriptionHistory: Sendable {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func record(text: String, durationMs: Int, latencyMs: Int) throws {
        let entry = TranscriptionEntry(text: text, durationMs: durationMs, latencyMs: latencyMs)
        try database.write { db in
            try entry.save(db) // save() works on let bindings unlike insert() which is mutating
        }
    }

    public func recent(limit: Int = 5) throws -> [TranscriptionEntry] {
        try database.read { db in
            try TranscriptionEntry
                .order(Column("created_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TranscriptionHistoryTests 2>&1 | tail -10`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/VoxOpsCore/Storage/TranscriptionHistory.swift Tests/VoxOpsCoreTests/TranscriptionHistoryTests.swift
git commit -m "feat: add TranscriptionHistory with record and recent"
```

---

### Task 3: TranscriptionHistory — Usage Stats and Streak

**Files:**
- Modify: `Sources/VoxOpsCore/Storage/TranscriptionHistory.swift`
- Test: `Tests/VoxOpsCoreTests/TranscriptionHistoryTests.swift` (add tests)

- [ ] **Step 1: Write failing tests — todayStats and streak**

Add to `TranscriptionHistoryTests.swift`:

```swift
@Test("todayStats returns count, duration, latency, and streak")
func todayStats() throws {
    let db = try Database(inMemory: true)
    let history = TranscriptionHistory(database: db)
    try history.record(text: "a", durationMs: 1000, latencyMs: 200)
    try history.record(text: "b", durationMs: 2000, latencyMs: 400)
    let stats = try history.todayStats()
    #expect(stats.count == 2)
    #expect(stats.totalDurationMs == 3000)
    #expect(stats.avgLatencyMs == 300)
    #expect(stats.streakDays >= 1)
}

@Test("todayStats returns zeros when no transcriptions")
func todayStatsEmpty() throws {
    let db = try Database(inMemory: true)
    let history = TranscriptionHistory(database: db)
    let stats = try history.todayStats()
    #expect(stats.count == 0)
    #expect(stats.totalDurationMs == 0)
    #expect(stats.avgLatencyMs == 0)
    #expect(stats.streakDays == 0)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TranscriptionHistoryTests 2>&1 | tail -10`
Expected: FAIL — todayStats not defined

- [ ] **Step 3: Add UsageStats struct and todayStats/streakDays methods**

Add `UsageStats` struct and methods to `TranscriptionHistory.swift`:

```swift
public struct UsageStats: Sendable {
    public let count: Int
    public let totalDurationMs: Int
    public let avgLatencyMs: Int
    public let streakDays: Int

    public init(count: Int = 0, totalDurationMs: Int = 0, avgLatencyMs: Int = 0, streakDays: Int = 0) {
        self.count = count
        self.totalDurationMs = totalDurationMs
        self.avgLatencyMs = avgLatencyMs
        self.streakDays = streakDays
    }
}
```

Add to `TranscriptionHistory`:

```swift
public func todayStats() throws -> UsageStats {
    let (count, totalMs, avgMs) = try database.read { db -> (Int, Int, Int) in
        let row = try Row.fetchOne(db, sql: """
            SELECT COUNT(*) as cnt,
                   COALESCE(SUM(duration_ms), 0) as total,
                   COALESCE(CAST(AVG(latency_ms) AS INTEGER), 0) as avg
            FROM transcriptions
            WHERE date(created_at, 'localtime') = date('now', 'localtime')
            """)
        return (
            row?["cnt"] ?? 0,
            row?["total"] ?? 0,
            row?["avg"] ?? 0
        )
    }
    let streak = try streakDays()
    return UsageStats(count: count, totalDurationMs: totalMs, avgLatencyMs: avgMs, streakDays: streak)
}

public func streakDays() throws -> Int {
    let dates: [String] = try database.read { db in
        try String.fetchAll(db, sql: """
            SELECT DISTINCT date(created_at, 'localtime') as d
            FROM transcriptions
            ORDER BY d DESC
            """)
    }
    guard !dates.isEmpty else { return 0 }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = .current
    let today = formatter.string(from: Date())
    guard dates.first == today else { return 0 }
    var streak = 1
    var prev = today
    for i in 1..<dates.count {
        guard let prevDate = formatter.date(from: prev),
              let expected = Calendar.current.date(byAdding: .day, value: -1, to: prevDate) else { break }
        let expectedStr = formatter.string(from: expected)
        if dates[i] == expectedStr {
            streak += 1
            prev = dates[i]
        } else {
            break
        }
    }
    return streak
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TranscriptionHistoryTests 2>&1 | tail -10`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `swift test 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/VoxOpsCore/Storage/TranscriptionHistory.swift Tests/VoxOpsCoreTests/TranscriptionHistoryTests.swift
git commit -m "feat: add usage stats and streak tracking to TranscriptionHistory"
```

---

### Task 4: TextFormatter Protocol and DictationFormatter

**Files:**
- Create: `Sources/VoxOpsCore/Pipeline/TextFormatter.swift`
- Modify: `Sources/VoxOpsCore/Pipeline/RawFormatter.swift:3` (add protocol conformance)
- Create: `Sources/VoxOpsCore/Pipeline/DictationFormatter.swift`
- Create: `Sources/VoxOpsCore/Pipeline/FormatterRegistry.swift`
- Test: `Tests/VoxOpsCoreTests/DictationFormatterTests.swift`
- Test: `Tests/VoxOpsCoreTests/FormatterRegistryTests.swift`

- [ ] **Step 1: Create TextFormatter protocol**

```swift
// Sources/VoxOpsCore/Pipeline/TextFormatter.swift
import Foundation

public protocol TextFormatter: Sendable {
    var name: String { get }
    func format(_ text: String) -> String
}
```

- [ ] **Step 2: Add protocol conformance to RawFormatter**

In `Sources/VoxOpsCore/Pipeline/RawFormatter.swift`, change:
```swift
public struct RawFormatter: Sendable {
```
to:
```swift
public struct RawFormatter: TextFormatter {
    public var name: String { "Raw" }
```

- [ ] **Step 3: Verify existing RawFormatter tests still pass**

Run: `swift test --filter RawFormatterTests 2>&1 | tail -10`
Expected: PASS (no behavioral change)

- [ ] **Step 4: Write failing DictationFormatter tests**

```swift
// Tests/VoxOpsCoreTests/DictationFormatterTests.swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("DictationFormatter")
struct DictationFormatterTests {
    let formatter = DictationFormatter()

    @Test("name is Dictation")
    func name() {
        #expect(formatter.name == "Dictation")
    }

    @Test("capitalizes first letter")
    func capitalizes() {
        #expect(formatter.format("hello world") == "Hello world")
    }

    @Test("removes filler um at start of sentence")
    func removesUm() {
        #expect(formatter.format("um hello world") == "Hello world")
    }

    @Test("removes filler uh at start of sentence")
    func removesUh() {
        #expect(formatter.format("uh this is a test") == "This is a test")
    }

    @Test("removes filler like at start of sentence")
    func removesLike() {
        #expect(formatter.format("like I was saying") == "I was saying")
    }

    @Test("removes filler after sentence boundary")
    func removesFillerAfterPeriod() {
        #expect(formatter.format("ok. um what next") == "Ok. What next")
    }

    @Test("preserves like in middle of sentence")
    func preservesLikeInMiddle() {
        #expect(formatter.format("I like this") == "I like this")
    }

    @Test("handles empty string")
    func handlesEmpty() {
        #expect(formatter.format("") == "")
    }

    @Test("collapses multiple spaces")
    func collapsesSpaces() {
        #expect(formatter.format("hello   world") == "Hello world")
    }
}
```

- [ ] **Step 5: Run test to verify it fails**

Run: `swift test --filter DictationFormatterTests 2>&1 | tail -10`
Expected: FAIL — DictationFormatter not defined

- [ ] **Step 6: Implement DictationFormatter**

```swift
// Sources/VoxOpsCore/Pipeline/DictationFormatter.swift
import Foundation

public struct DictationFormatter: TextFormatter {
    public var name: String { "Dictation" }
    private let rawFormatter = RawFormatter()
    private let fillerPattern: NSRegularExpression

    public init() {
        // Matches filler words at start of string or after sentence-ending punctuation
        fillerPattern = try! NSRegularExpression(
            pattern: #"(?i)(?:^|(?<=[.!?]\s))(um|uh|like|you know|basically|actually|so,)\s*"#,
            options: []
        )
    }

    public func format(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty { return result }
        // Remove fillers first
        result = fillerPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: ""
        )
        // Then apply raw formatting (whitespace collapse, capitalization)
        return rawFormatter.format(result)
    }
}
```

- [ ] **Step 7: Run DictationFormatter tests**

Run: `swift test --filter DictationFormatterTests 2>&1 | tail -10`
Expected: PASS

- [ ] **Step 8: Write FormatterRegistry tests**

```swift
// Tests/VoxOpsCoreTests/FormatterRegistryTests.swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("FormatterRegistry")
struct FormatterRegistryTests {
    let registry = FormatterRegistry()

    @Test("available returns Raw and Dictation")
    func available() {
        let names = registry.available.map { $0.name }
        #expect(names == ["Raw", "Dictation"])
    }

    @Test("active returns formatter by name")
    func activeByName() {
        let formatter = registry.active(name: "Dictation")
        #expect(formatter.name == "Dictation")
    }

    @Test("active falls back to Raw for unknown name")
    func fallback() {
        let formatter = registry.active(name: "nonexistent")
        #expect(formatter.name == "Raw")
    }
}
```

- [ ] **Step 9: Implement FormatterRegistry**

```swift
// Sources/VoxOpsCore/Pipeline/FormatterRegistry.swift
import Foundation

public struct FormatterRegistry: Sendable {
    public let available: [any TextFormatter] = [RawFormatter(), DictationFormatter()]

    public init() {}

    public func active(name: String) -> any TextFormatter {
        available.first { $0.name == name } ?? RawFormatter()
    }
}
```

- [ ] **Step 10: Run all formatter tests**

Run: `swift test --filter "FormatterRegistryTests|DictationFormatterTests|RawFormatterTests" 2>&1 | tail -10`
Expected: PASS

- [ ] **Step 11: Commit**

```bash
git add Sources/VoxOpsCore/Pipeline/TextFormatter.swift Sources/VoxOpsCore/Pipeline/RawFormatter.swift Sources/VoxOpsCore/Pipeline/DictationFormatter.swift Sources/VoxOpsCore/Pipeline/FormatterRegistry.swift Tests/VoxOpsCoreTests/DictationFormatterTests.swift Tests/VoxOpsCoreTests/FormatterRegistryTests.swift
git commit -m "feat: add TextFormatter protocol, DictationFormatter, and FormatterRegistry"
```

---

### Task 5: AudioDeviceManager — CoreAudio Device Enumeration

**Files:**
- Create: `Sources/VoxOpsCore/Audio/AudioDeviceManager.swift`
- Modify: `Sources/VoxOpsCore/Audio/AudioManager.swift:64-67` (move AudioDevice struct to its own context)
- Test: `Tests/VoxOpsCoreTests/AudioDeviceManagerTests.swift`

- [ ] **Step 1: Write test — availableInputDevices returns at least one device**

```swift
// Tests/VoxOpsCoreTests/AudioDeviceManagerTests.swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("AudioDeviceManager")
struct AudioDeviceManagerTests {
    @Test("availableInputDevices returns at least one device on macOS hardware")
    func enumeratesDevices() {
        let manager = AudioDeviceManager()
        let devices = manager.availableInputDevices()
        // Every Mac has at least a built-in mic
        #expect(!devices.isEmpty)
        #expect(devices.allSatisfy { !$0.name.isEmpty })
        #expect(devices.allSatisfy { !$0.id.isEmpty })
    }

    @Test("defaultDevice returns a device")
    func defaultDevice() {
        let manager = AudioDeviceManager()
        let device = manager.defaultDevice()
        #expect(device != nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AudioDeviceManagerTests 2>&1 | tail -10`
Expected: FAIL — AudioDeviceManager not defined

- [ ] **Step 3: Implement AudioDeviceManager**

```swift
// Sources/VoxOpsCore/Audio/AudioDeviceManager.swift
import Foundation
import CoreAudio

public final class AudioDeviceManager: @unchecked Sendable {
    /// Called on main thread when the device list changes (device plugged/unplugged)
    public var onDevicesChanged: (() -> Void)?

    public init() {
        // Register CoreAudio property listener for device list changes
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.onDevicesChanged?()
        }
    }

    public func availableInputDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize) == noErr else {
            return []
        }
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }
        return deviceIDs.compactMap { deviceID -> AudioDevice? in
            guard hasInputStreams(deviceID) else { return nil }
            guard let name = deviceName(deviceID) else { return nil }
            return AudioDevice(id: String(deviceID), name: name)
        }
    }

    public func defaultDevice() -> AudioDevice? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceID) == noErr else {
            return nil
        }
        guard let name = deviceName(deviceID) else { return nil }
        return AudioDevice(id: String(deviceID), name: name)
    }

    private func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize) == noErr else {
            return false
        }
        return dataSize > 0
    }

    private func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name) == noErr else {
            return nil
        }
        return name as String
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AudioDeviceManagerTests 2>&1 | tail -10`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/VoxOpsCore/Audio/AudioDeviceManager.swift Tests/VoxOpsCoreTests/AudioDeviceManagerTests.swift
git commit -m "feat: add AudioDeviceManager for CoreAudio input device enumeration"
```

---

### Task 6: AudioManager — Mid-Recording Device Switching

**Files:**
- Modify: `Sources/VoxOpsCore/Audio/AudioManager.swift`

- [ ] **Step 1: Add switchInput method to AudioManager**

Add to `AudioManager` class after `stopRecording()`:

```swift
/// Switch audio input device. Pass empty string for system default.
/// Handles CoreAudio device ID conversion internally — callers pass the string ID from AudioDevice.
public func switchInput(to deviceIdString: String) {
    lock.lock()
    let wasRecording = isRecording
    lock.unlock()

    // Set the desired input device at the system level if specified
    if !deviceIdString.isEmpty, let deviceID = UInt32(deviceIdString) {
        var id = deviceID
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &id
        )
    }
    // Note: selecting "System Default" (empty string) does not change the system setting —
    // it just means "use whatever the OS default is" on the next engine start.

    if wasRecording {
        // Remove tap and stop current engine, but preserve recorded data
        lock.lock()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        lock.unlock()

        // Create new engine — it picks up the current system default input device
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let busFormat = inputNode.outputFormat(forBus: 0)
        let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: busFormat) { [weak self] buffer, _ in
            guard let self else { return }
            if let converted = self.convert(buffer: buffer, to: recordingFormat) {
                self.lock.lock()
                self.recordedData.append(converted)
                self.lock.unlock()
            }
        }
        try? engine.start()
        lock.lock()
        self.audioEngine = engine
        lock.unlock()
    }
}
```

Note: `import CoreAudio` must be added to the imports of `AudioManager.swift`.

- [ ] **Step 2: Run full test suite to verify no regressions**

Run: `swift test 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add Sources/VoxOpsCore/Audio/AudioManager.swift
git commit -m "feat: add mid-recording input device switching to AudioManager"
```

---

### Task 7: AppState — Integrate History, Formatters, and Devices

**Files:**
- Modify: `VoxOpsApp/AppState.swift`

This task wires all new core components into AppState. No new tests — AppState is UI-layer and tested via the existing integration flow.

- [ ] **Step 1: Add new published properties and private state**

Add to AppState after existing `@Published` declarations:

```swift
@Published var activeFormatterName: String = "Raw"
@Published var selectedDeviceId: String = ""
@Published var usageStats: UsageStats = UsageStats()
@Published var recentTranscriptions: [TranscriptionEntry] = []
@Published var availableDevices: [AudioDevice] = []
@Published var historyLimit: Int = 5
```

Add private properties:

```swift
private var transcriptionHistory: TranscriptionHistory?
private var audioDeviceManager: AudioDeviceManager?
private let formatterRegistry = FormatterRegistry()
```

- [ ] **Step 2: Update setup() to initialize new components**

In `setup()`, after `self.settingsStore = SettingsStore(database: db)`:

```swift
self.transcriptionHistory = TranscriptionHistory(database: db)
let deviceManager = AudioDeviceManager()
deviceManager.onDevicesChanged = { [weak self] in
    self?.refreshDevices()
    // If selected device is gone, fall back to system default
    if let selectedId = self?.selectedDeviceId, !selectedId.isEmpty,
       !(self?.availableDevices.contains { $0.id == selectedId } ?? false) {
        self?.setAudioDevice("")
    }
}
self.audioDeviceManager = deviceManager
```

- [ ] **Step 3: Update loadSettings() to load new settings**

Add to `loadSettings()`:

```swift
// Load formatter
if let name = try? store.getString("active_formatter") {
    activeFormatterName = name
}
// Load audio device
if let id = try? store.getString("audio_device_id") {
    selectedDeviceId = id
}
// Load history limit
if let limitStr = try? store.getString("history_limit"), let limit = Int(limitStr) {
    historyLimit = limit
}
```

After `loadSettings()` call in `setup()`, add:

```swift
refreshStats()
refreshDevices()
```

- [ ] **Step 4: Add new methods**

```swift
func setFormatter(_ name: String) {
    guard let store = settingsStore else { return }
    try? store.setString("active_formatter", value: name)
    activeFormatterName = name
}

func setAudioDevice(_ id: String) {
    guard let store = settingsStore else { return }
    try? store.setString("audio_device_id", value: id)
    selectedDeviceId = id
    audioManager?.switchInput(to: id) // AudioManager handles String -> AudioDeviceID conversion internally
}

func setHistoryLimit(_ limit: Int) {
    guard let store = settingsStore else { return }
    try? store.setString("history_limit", value: String(limit))
    historyLimit = limit
    refreshStats()
}

func refreshStats() {
    guard let history = transcriptionHistory else { return }
    usageStats = (try? history.todayStats()) ?? UsageStats()
    recentTranscriptions = (try? history.recent(limit: historyLimit)) ?? []
}

func refreshDevices() {
    availableDevices = audioDeviceManager?.availableInputDevices() ?? []
}
```

- [ ] **Step 5: Update stopListeningAndProcess() to record transcriptions and use formatter**

Replace the formatting line:
```swift
let formatted = rawFormatter?.format(result.text) ?? result.text
```
with:
```swift
let formatted = formatterRegistry.active(name: activeFormatterName).format(result.text)
```

After the successful injection block (after `voxState = .success`), add:
```swift
let latencyMs = Int(Date().timeIntervalSince(processStart) * 1000)
let durationMs = Int(audio.duration * 1000)
try? transcriptionHistory?.record(text: formatted, durationMs: durationMs, latencyMs: latencyMs)
refreshStats()
```

Add `let processStart = Date()` right before the `backend.transcribe()` call.

Remove the `rawFormatter` property — it's replaced by `formatterRegistry`.

- [ ] **Step 6: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build complete

- [ ] **Step 7: Commit**

```bash
git add VoxOpsApp/AppState.swift
git commit -m "feat: integrate history, formatters, and device management into AppState"
```

---

### Task 8: Menu Bar UI — Tabbed Layout

**Files:**
- Modify: `VoxOpsApp/Views/MenuBarView.swift` (refactor to tabs + shared header/footer)
- Create: `VoxOpsApp/Views/MenuBarMainTab.swift`
- Create: `VoxOpsApp/Views/MenuBarStatsTab.swift`

- [ ] **Step 1: Create MenuBarMainTab**

```swift
// VoxOpsApp/Views/MenuBarMainTab.swift
import SwiftUI
import VoxOpsCore

struct MenuBarMainTab: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Mode toggle
            VStack(alignment: .leading, spacing: 4) {
                Text("MODE").font(.system(size: 10)).foregroundStyle(.secondary).tracking(0.5)
                Picker("Mode", selection: Binding(
                    get: { appState.activeFormatterName },
                    set: { appState.setFormatter($0) }
                )) {
                    Text("Raw").tag("Raw")
                    Text("Dictation").tag("Dictation")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            // Backend toggle
            VStack(alignment: .leading, spacing: 4) {
                Text("BACKEND").font(.system(size: 10)).foregroundStyle(.secondary).tracking(0.5)
                Picker("Backend", selection: $appState.selectedBackend) {
                    Text("whisper.cpp").tag("whisper.cpp")
                    Text("MLX").tag("mlx-whisper")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            // Mic picker
            VStack(alignment: .leading, spacing: 4) {
                Text("MICROPHONE").font(.system(size: 10)).foregroundStyle(.secondary).tracking(0.5)
                Picker("Microphone", selection: Binding(
                    get: { appState.selectedDeviceId },
                    set: { appState.setAudioDevice($0) }
                )) {
                    Text("System Default").tag("")
                    ForEach(appState.availableDevices, id: \.id) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .labelsHidden()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if !appState.lastTranscript.isEmpty {
                Divider()
                Text(appState.lastTranscript)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }
        }
    }
}
```

- [ ] **Step 2: Create MenuBarStatsTab**

```swift
// VoxOpsApp/Views/MenuBarStatsTab.swift
import SwiftUI
import VoxOpsCore

struct MenuBarStatsTab: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Today's stats
            VStack(alignment: .leading, spacing: 4) {
                Text("TODAY").font(.system(size: 10)).foregroundStyle(.secondary).tracking(0.5)
                statsRow("Transcriptions", value: "\(appState.usageStats.count)")
                statsRow("Audio time", value: formatDuration(appState.usageStats.totalDurationMs))
                statsRow("Avg latency", value: String(format: "%.1fs", Double(appState.usageStats.avgLatencyMs) / 1000.0))
                if appState.usageStats.streakDays >= 2 {
                    statsRow("Streak", value: "\(appState.usageStats.streakDays) days \u{1F525}")
                } else if appState.usageStats.streakDays == 1 {
                    statsRow("Streak", value: "1 day")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            // Recent transcriptions
            VStack(alignment: .leading, spacing: 4) {
                Text("RECENT").font(.system(size: 10)).foregroundStyle(.secondary).tracking(0.5)
                if appState.recentTranscriptions.isEmpty {
                    Text("No transcriptions yet")
                        .font(.caption).foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(appState.recentTranscriptions, id: \.id) { entry in
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.text, forType: .string)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.text)
                                    .font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 4) {
                                    Text(relativeTime(entry.date))
                                    Text("·")
                                    Text(String(format: "%.1fs", Double(entry.latencyMs) / 1000.0))
                                }
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    private func statsRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .semibold))
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}
```

- [ ] **Step 3: Refactor MenuBarView to use tabs**

Replace the entire body of `MenuBarView` with:

```swift
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            HStack {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text("VoxOps").font(.headline)
                Spacer()
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            // Tab bar
            HStack(spacing: 0) {
                tabButton("Main", tab: 0)
                tabButton("Stats", tab: 1)
            }
            .padding(.horizontal, 12)

            Divider()

            // Tab content
            if selectedTab == 0 {
                MenuBarMainTab(appState: appState)
            } else {
                MenuBarStatsTab(appState: appState)
            }

            Divider()

            // Shared footer
            Button("Settings...") { appState.openSettings() }
                .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            Button("Quit VoxOps") { NSApplication.shared.terminate(nil) }
                .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, 12).padding(.bottom, 6)
        }
        .frame(width: 240)
    }

    private func tabButton(_ label: String, tab: Int) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                Rectangle()
                    .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch appState.voxState {
        case .idle: return .green; case .listening: return .red
        case .processing: return .orange; case .success: return .green; case .error: return .red
        }
    }

    private var statusText: String {
        switch appState.voxState {
        case .idle: return "Ready"; case .listening: return "Listening..."
        case .processing: return "Processing..."; case .success: return "Done"; case .error(let msg): return msg
        }
    }
}
```

- [ ] **Step 4: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build complete

- [ ] **Step 5: Commit**

```bash
git add VoxOpsApp/Views/MenuBarView.swift VoxOpsApp/Views/MenuBarMainTab.swift VoxOpsApp/Views/MenuBarStatsTab.swift
git commit -m "feat: refactor menu bar to tabbed layout with Main and Stats tabs"
```

---

### Task 9: Settings View — History Limit and Mic Picker

**Files:**
- Modify: `VoxOpsApp/Views/SettingsView.swift`

- [ ] **Step 1: Add History section to General tab**

In `SettingsView.swift`, in the `generalTab` computed property, add after the "After Injection" section:

```swift
Section("History") {
    Stepper("Show last \(appState.historyLimit) transcriptions", value: Binding(
        get: { appState.historyLimit },
        set: { appState.setHistoryLimit($0) }
    ), in: 1...20)
}
```

- [ ] **Step 2: Add Mic picker to Audio tab**

Replace the `audioTab` computed property:

```swift
private var audioTab: some View {
    Form {
        Section("Microphone") {
            Picker("Input Device", selection: Binding(
                get: { appState.selectedDeviceId },
                set: { appState.setAudioDevice($0) }
            )) {
                Text("System Default").tag("")
                ForEach(appState.availableDevices, id: \.id) { device in
                    Text(device.name).tag(device.id)
                }
            }
        }
    }.padding()
}
```

- [ ] **Step 3: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build complete

- [ ] **Step 4: Commit**

```bash
git add VoxOpsApp/Views/SettingsView.swift
git commit -m "feat: add history limit stepper and mic picker to Settings"
```

---

### Task 10: XcodeGen, Full Build, and Integration Verification

**Files:**
- Modify: `project.yml` (if new files need explicit listing)

- [ ] **Step 1: Run full test suite**

Run: `swift test 2>&1 | tail -10`
Expected: All tests pass

- [ ] **Step 2: Regenerate Xcode project**

Run: `xcodegen generate 2>&1`
Expected: "Created project at .../VoxOps.xcodeproj"

- [ ] **Step 3: Build via xcodebuild**

Run: `xcodebuild -project VoxOps.xcodeproj -scheme VoxOpsApp -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Launch and manual verification**

Run: `open /path/to/DerivedData/.../VoxOpsApp.app`

Manual checks:
- Menu bar icon appears
- Click icon: dropdown shows with Main/Stats tab bar
- Main tab: mode toggle (Raw/Dictation), backend toggle, mic picker, last transcript
- Stats tab: today's stats (all zeros initially), empty recent list
- Click Settings: window opens with History stepper and Mic picker in Audio tab
- Do a test transcription (hold ⌘Space): text appears, stats update, history populates
- Switch to Stats tab: transcription visible, click to copy works

- [ ] **Step 5: Commit**

```bash
git add project.yml
git commit -m "chore: update project.yml for menu bar enhancements"
```

Note: Only commit project.yml if it needed changes. All source files should already be committed from prior tasks.
