# Menu Bar Enhancements Design

## Goal

Enhance the menu bar dropdown with five features: STT backend picker, mic input selector, transcription history, formatting modes, and usage stats. Organize via a tabbed interface (Main / Stats).

## Architecture

Thin dropdown, fat core. All new logic lives in VoxOpsCore with proper tests. The dropdown tabs are pure SwiftUI views binding to AppState published properties. AppState stays a thin coordinator.

## Data Layer — TranscriptionHistory

New SQLite table `transcriptions` added via GRDB migration in `Database.swift`:

```sql
CREATE TABLE transcriptions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    text TEXT NOT NULL,
    duration_ms INTEGER NOT NULL,
    latency_ms INTEGER NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
)
```

`TranscriptionHistory` class (`Sources/VoxOpsCore/Storage/TranscriptionHistory.swift`):
- `init(database: Database)` — takes existing Database instance
- `record(text:durationMs:latencyMs:)` — inserts a row
- `recent(limit: Int = 5) -> [TranscriptionEntry]` — returns last N entries ordered by `created_at DESC`
- `todayStats() -> UsageStats` — single query: `SELECT COUNT(*), COALESCE(SUM(duration_ms),0), COALESCE(AVG(latency_ms),0) FROM transcriptions WHERE date(created_at, 'localtime') = date('now', 'localtime')`
- `streakDays() -> Int` — queries `SELECT DISTINCT date(created_at, 'localtime') as d FROM transcriptions ORDER BY d DESC`, walks backwards from today counting consecutive days

```swift
public struct TranscriptionEntry: Sendable, Codable, FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "transcriptions"
    public let id: Int64
    public let text: String
    public let durationMs: Int
    public let latencyMs: Int
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, text
        case durationMs = "duration_ms"
        case latencyMs = "latency_ms"
        case createdAt = "created_at"
    }
}

public struct UsageStats: Sendable {
    public let count: Int
    public let totalDurationMs: Int
    public let avgLatencyMs: Int
    public let streakDays: Int
}
```

The display limit in the dropdown defaults to 5, stored in SettingsStore as `"history_limit"` (string integer). Configurable via a stepper (1-20) in Settings under a "History" section.

AppState calls `transcriptionHistory.record()` after each successful transcription, passing audio duration converted from `AudioBuffer.duration` (seconds) to milliseconds via `Int(audio.duration * 1000)`, and processing latency (measured as wall-clock time from `stopRecording()` to transcription result, also in milliseconds).

**Error handling:** All `TranscriptionHistory` methods are marked `throws` since they perform GRDB database I/O. Callers catch errors and log/ignore — a failed stats query should never block the transcription pipeline. `record()` failures are logged but do not surface to the user. `recent()` and `todayStats()` return empty defaults on error.

**Assembling UsageStats:** `todayStats()` internally calls `streakDays()` and returns a fully populated `UsageStats` struct in a single public method. Callers never need to assemble the struct manually.

**Timestamp storage:** `created_at` is stored as UTC (`strftime(...'now')`). Queries use `date(created_at, 'localtime')` to compare against local dates. This is intentional — UTC storage with localtime queries is the correct approach for cross-timezone consistency.

## Formatting — TextFormatter Protocol

```swift
public protocol TextFormatter: Sendable {
    var name: String { get }
    func format(_ text: String) -> String
}
```

Two implementations:
- `RawFormatter` (existing, conforms to protocol) — add `var name: String { "Raw" }` property, trims whitespace, collapses runs, capitalizes sentences
- `DictationFormatter` (new, `Sources/VoxOpsCore/Pipeline/DictationFormatter.swift`) — everything Raw does plus: trims filler words, capitalizes after line breaks

**DictationFormatter filler word rules:**
- Remove these words when they appear at the start of a sentence (after `.?!` or start of string, ignoring whitespace): "um", "uh", "uh", "like", "you know", "basically", "actually", "so" (only when followed by comma)
- Pattern: `(?i)(?<=^|[.!?]\s+)(um|uh|like|you know|basically|actually|so,)\s*` — applied as a regex replacement pass before the standard RawFormatter pipeline
- Edge case: if removing the filler leaves an empty sentence, collapse the whitespace

`FormatterRegistry` (`Sources/VoxOpsCore/Pipeline/FormatterRegistry.swift`):
- `available: [any TextFormatter]` — returns `[RawFormatter(), DictationFormatter()]`
- `active(name: String) -> any TextFormatter` — returns formatter by name, falls back to RawFormatter
- No mutable state — the active formatter name is stored in SettingsStore as `"active_formatter"` (default `"Raw"`)

AppState holds `@Published var activeFormatterName: String = "Raw"` and uses `formatterRegistry.active(name: activeFormatterName).format(text)` in the pipeline. The mode toggle in the dropdown updates `activeFormatterName` and persists it.

## Audio — AudioDeviceManager

New `AudioDeviceManager` (`Sources/VoxOpsCore/Audio/AudioDeviceManager.swift`):

Uses CoreAudio C API (`AudioObjectGetPropertyData`) to enumerate input devices:
- `availableInputDevices() -> [AudioDevice]` — lists all audio input devices. Uses `kAudioHardwarePropertyDevices` + `kAudioDevicePropertyStreams` (input scope) to filter inputs, `kAudioObjectPropertyName` for display names.
- `defaultDevice() -> AudioDevice?` — reads `kAudioHardwarePropertyDefaultInputDevice`

The existing `AudioDevice` struct (already in AudioManager.swift) has `id: String` and `name: String`. The `id` is the `AudioDeviceID` converted to string.

Device selection persisted in SettingsStore as `"audio_device_id"` (string, empty = system default).

**Immediate mid-recording switching** in `AudioManager`:
- New method `switchInput(to deviceID: AudioDeviceID?)` — the `inputNode` is bound at engine creation time and cannot be reassigned. To switch devices mid-recording:
  1. Remove tap on bus 0
  2. Stop and release the old `AVAudioEngine` entirely
  3. Set the system default input device via `AudioObjectSetPropertyData` on `kAudioHardwarePropertyDefaultInputDevice` if a specific device is requested, or restore system default
  4. Create a new `AVAudioEngine` instance
  5. Re-query `inputNode.outputFormat(forBus: 0)` — the new device may have a different sample rate or channel count
  6. Reinstall the tap with the new bus format and the same 16kHz mono conversion target
  7. Restart the engine
- The existing `recordedData` buffer is preserved — new samples from the new device append to it. There will be a brief audio gap (~50-100ms) during the switch, which is acceptable.
- If the new device has a different native sample rate, the `AVAudioConverter` in the tap callback already handles resampling to the target 16kHz mono format, so no additional format handling is needed.
- If the selected device is unavailable (disconnected), falls back to system default.

**Device disconnect detection**: `AudioDeviceManager` registers a CoreAudio property listener on `kAudioHardwarePropertyDevices`. CoreAudio callbacks fire on arbitrary threads, so the listener dispatches to `DispatchQueue.main` before publishing updates. AppState checks if the selected device is still present; if not, clears the selection (falls back to default) and updates the UI.

## Menu Bar UI — Tabbed Dropdown

`MenuBarView` refactored into a tabbed layout.

**Structure:**
```
VStack {
    StatusHeader          // dot + "VoxOps" + state — always visible
    TabView {
        MainTab
        StatsTab
    }
    SharedFooter          // Settings, Quit, version — always visible
}
.frame(width: 240)
```

**MainTab** (`MenuBarMainTab.swift`):
- Mode toggle — segmented `Picker` with Raw/Dictation, binds to `appState.activeFormatterName`
- Backend toggle — segmented `Picker` with whisper.cpp/MLX, binds to `appState.selectedBackend`
- Mic picker — `Picker` bound to `appState.selectedDeviceId`, items from `audioDeviceManager.availableInputDevices()`, first option "System Default"
- Last transcript — single line, secondary text

**StatsTab** (`MenuBarStatsTab.swift`):
- Today section — count, total audio time (formatted as "Xm Ys"), avg latency ("X.Xs"), streak ("N days" + fire emoji when >= 2)
- Recent section — list of `TranscriptionEntry` items, each showing truncated text + relative time + latency. Tap copies text to clipboard via `NSPasteboard`.

**SharedFooter**: Settings button, Quit button, version label. Identical on both tabs.

Tab styling: SwiftUI `TabView` with manual tab bar (not `.tabViewStyle` which doesn't fit well in a MenuBarExtra). Instead, a custom `HStack` of tab buttons at the top with an underline indicator, controlling a `@State var selectedTab` that switches between `MainTab` and `StatsTab` content.

## Settings Additions

New sections in the General tab of SettingsView:

**History section:**
- Stepper "Show last N transcriptions" bound to history limit (1-20, default 5)
- Persisted as `"history_limit"` in SettingsStore

**Microphone section** (in Audio tab):
- Same picker as dropdown, serves as fallback/discoverable location
- Shows current device name or "System Default"

The existing STT Backend picker in the General tab of SettingsView remains as-is — it serves as a discoverable fallback. The dropdown's backend toggle is a convenience duplicate. Mode (formatter) selection does not need a Settings entry since it's prominently accessible in the dropdown.

## AppState Changes

New published properties:
- `@Published var activeFormatterName: String = "Raw"`
- `@Published var selectedDeviceId: String = ""` (empty = system default)
- `@Published var usageStats: UsageStats = UsageStats(count: 0, totalDurationMs: 0, avgLatencyMs: 0, streakDays: 0)`
- `@Published var recentTranscriptions: [TranscriptionEntry] = []`
- `@Published var availableDevices: [AudioDevice] = []`
- `@Published var historyLimit: Int = 5`

New private properties:
- `transcriptionHistory: TranscriptionHistory?`
- `audioDeviceManager: AudioDeviceManager?`
- `formatterRegistry: FormatterRegistry`

`setup()` initializes `TranscriptionHistory` and `AudioDeviceManager`, loads settings, refreshes stats and device list.

`stopListeningAndProcess()` changes:
- Captures start time before `backend.transcribe()`
- After success, computes `latencyMs` and calls `transcriptionHistory.record()`
- Refreshes `usageStats` and `recentTranscriptions`
- Uses `formatterRegistry.active(name: activeFormatterName).format(text)` instead of `rawFormatter`

New methods:
- `setFormatter(_ name: String)` — persists, updates published property
- `setAudioDevice(_ id: String)` — persists, calls `audioManager.switchInput()`, updates published property
- `setHistoryLimit(_ limit: Int)` — persists, refreshes `recentTranscriptions`
- `refreshStats()` — reloads `usageStats` and `recentTranscriptions` from `TranscriptionHistory`
- `refreshDevices()` — reloads `availableDevices` from `AudioDeviceManager`

## Files Affected

| File | Change |
|------|--------|
| `Sources/VoxOpsCore/Storage/Database.swift` | Add migration for `transcriptions` table |
| `Sources/VoxOpsCore/Storage/TranscriptionHistory.swift` | New — history recording and stats queries |
| `Sources/VoxOpsCore/Pipeline/TextFormatter.swift` | New — protocol definition |
| `Sources/VoxOpsCore/Pipeline/RawFormatter.swift` | Conform to TextFormatter protocol |
| `Sources/VoxOpsCore/Pipeline/DictationFormatter.swift` | New — dictation formatting |
| `Sources/VoxOpsCore/Pipeline/FormatterRegistry.swift` | New — formatter lookup |
| `Sources/VoxOpsCore/Audio/AudioDeviceManager.swift` | New — CoreAudio device enumeration and monitoring |
| `Sources/VoxOpsCore/Audio/AudioManager.swift` | Add `switchInput(to:)` for mid-recording device change |
| `VoxOpsApp/AppState.swift` | New properties, formatter/device/history integration |
| `VoxOpsApp/Views/MenuBarView.swift` | Refactor to tabbed layout with shared header/footer |
| `VoxOpsApp/Views/MenuBarMainTab.swift` | New — mode, backend, mic, last transcript |
| `VoxOpsApp/Views/MenuBarStatsTab.swift` | New — stats display and history list |
| `VoxOpsApp/Views/SettingsView.swift` | Add history limit stepper, mic picker in Audio tab |
| `Tests/VoxOpsCoreTests/TranscriptionHistoryTests.swift` | New — recording, recent, stats, streak |
| `Tests/VoxOpsCoreTests/DictationFormatterTests.swift` | New — filler word trimming, capitalization |
| `Tests/VoxOpsCoreTests/FormatterRegistryTests.swift` | New — lookup, fallback |
| `Tests/VoxOpsCoreTests/AudioDeviceManagerTests.swift` | New — test that `availableInputDevices()` returns non-empty list (integration test, requires audio hardware; skipped in CI via `#if !targetEnvironment(simulator)` guard). CoreAudio has no protocol abstraction so mocking is impractical — test at integration level only. |
