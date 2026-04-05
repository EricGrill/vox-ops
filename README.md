<h1 align="center">VoxOps</h1>

<p align="center">
  <strong>Push-to-talk voice → structured action → agent execution.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9+-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/SwiftUI-007AFF?style=for-the-badge&logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/macOS-14.0+-000000?style=for-the-badge&logo=apple&logoColor=white" alt="macOS">
  <img src="https://img.shields.io/badge/Apple_Silicon-M1+-333333?style=for-the-badge&logo=apple&logoColor=white" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/Whisper-Local_STT-4CAF50?style=for-the-badge" alt="Whisper">
</p>

---

VoxOps is a low-latency, local-first push-to-talk system for macOS that turns speech into text, structured commands, and agent actions. Hold a key, speak, release — text appears at your cursor, a command fires, or an agent job is dispatched.

Built for developers, prompt engineers, and anyone who operates AI-assisted workflows at the speed of speech.

## Architecture

```
[Global Hotkey]  (CGEvent tap)
      ↓
[Audio Capture]  (AVFoundation / CoreAudio → 16kHz mono PCM)
      ↓
[STT Engine]     (whisper.cpp CLI or MLX Whisper Python sidecar)
      ↓
[Intent Router]  (rule-based + optional LLM refinement)
  ├─ Raw Mode ──────→ Text Injection  (AXUIElement → cursor)
  ├─ Prompt Mode ───→ Formatter → Text Injection
  ├─ Command Mode ──→ Parser → JSON Output
  ├─ Agent Mode ────→ Adapter Protocol → External Systems
  └─ System Mode ───→ Safety Layer → Local Execution
```

### Core App + Sidecar Processes

| Layer | Components | Runtime |
|-------|-----------|---------|
| **Swift Core App** | HotkeyManager, AudioManager, IntentRouter, Formatter, InjectionLayer, ProfileManager, AgentAdapter, UI, Storage | Single process — hot path |
| **whisper.cpp Sidecar** | Compiled C++ CLI, stdin/stdout protocol | Managed child process |
| **MLX Whisper Sidecar** | Python server, Unix domain socket protocol | Managed child process |

The core app owns everything on the latency-critical path. STT engines run out-of-process for crash isolation and language flexibility (Python for MLX ecosystem, C++ for whisper.cpp).

## Output Modes

| Mode | Transform | Output | Destination |
|------|-----------|--------|-------------|
| **Raw** | Capitalize, trim, collapse spaces | Clean text | Cursor injection |
| **Prompt** | Grammar cleanup, filler removal, template | LLM-ready text | Cursor injection |
| **Command** | Schema matching (verb + noun + params) | Structured JSON | Cursor injection |
| **Agent** | Schema matching → adapter dispatch | JSON payload | External system |
| **System** | Workflow registry match → safety gate | Shell command | Local execution |

## Performance Targets

| Metric | Target |
|--------|--------|
| Hotkey response latency | < 50ms |
| Transcript ready (short utterance) | < 500ms |
| Text insertion after transcript | < 150ms |
| Command parse time (local) | < 700ms |
| Command parse time (remote) | < 1500ms |

## Text Injection

| Strategy | Method | When |
|----------|--------|------|
| **Primary** | Accessibility API (`AXUIElement`) | Direct text insertion at cursor position |
| **Fallback** | Clipboard paste (save → set → `Cmd+V` → restore) | When AX API fails or app doesn't support it |
| **Override** | Per-app profile | Configurable per bundle ID |

Supports: Terminal.app, iTerm2, VS Code, Cursor, Slack, Arc, Safari, and any app exposing `AXValue` or `AXSelectedText`.

## STT Backends

| Backend | Language | Protocol | Best For |
|---------|----------|----------|----------|
| **whisper.cpp** | C++ CLI | stdin: WAV path → stdout: JSON | Fast, lightweight, easy to install |
| **MLX Whisper** | Python | Unix domain socket | Apple Silicon optimized, HuggingFace models |

Both backends conform to the same Swift protocol:

```swift
protocol STTBackend: Sendable {
    var id: String { get }
    var status: BackendStatus { get }
    func transcribe(audio: AudioBuffer) async throws -> TranscriptResult
    func start() async throws
    func stop() async
}
```

Backend selection is configurable globally and per-profile. Auto mode prefers MLX Whisper on Apple Silicon with sufficient RAM, falls back to whisper.cpp.

## HUD States

| State | Visual | Trigger |
|-------|--------|---------|
| **Idle** | Dim gray dot | Default |
| **Listening** | Pulsing red glow | Hotkey held |
| **Processing** | Amber + spinning ring | STT transcribing |
| **Success** | Green flash → fade to idle | Text inserted |
| **Error** | Red shake + tooltip | Failure at any stage |

The HUD is a non-activating `NSPanel` — it never steals focus. Draggable to any screen position. Expands to show live transcript on hover.

## Agent Adapter System

Generic protocol for routing structured commands to any external system:

```swift
protocol AgentAdapter {
    var id: String { get }
    var displayName: String { get }
    func send(command: StructuredCommand) async throws -> DispatchResult
    func healthCheck() async -> AdapterStatus
}
```

| Built-in Adapter | Transport | Configuration |
|-----------------|-----------|---------------|
| **GenericREST** | HTTP POST | URL, method, headers, auth (Bearer/API key), field mapping |
| **GenericWebSocket** | Persistent socket | URL, reconnection, JSON messages |

Adding a new integration = implementing the `AgentAdapter` protocol. No changes to core app.

## Project Structure

```
VoxOps/
├── Package.swift                            # SPM package (core library)
├── project.yml                              # XcodeGen spec (full app build)
├── Sources/
│   └── VoxOpsCore/
│       ├── Audio/
│       │   ├── AudioBuffer.swift            # PCM data container + WAV export
│       │   └── AudioManager.swift           # AVFoundation mic recording
│       ├── Hotkey/
│       │   └── HotkeyManager.swift          # CGEvent tap — global push-to-talk
│       ├── Injection/
│       │   ├── TextInjector.swift            # Coordinator: AX → clipboard fallback
│       │   ├── AccessibilityInjector.swift   # AXUIElement text insertion
│       │   └── ClipboardInjector.swift       # Cmd+V with clipboard save/restore
│       ├── Pipeline/
│       │   ├── RawFormatter.swift            # Capitalize, trim, collapse spaces
│       │   └── VoxState.swift                # Pipeline state enum (drives HUD)
│       ├── Sidecar/
│       │   └── SidecarProcess.swift          # Generic child process lifecycle
│       ├── STT/
│       │   ├── STTBackend.swift              # Protocol + BackendStatus enum
│       │   ├── TranscriptResult.swift        # Result types + JSON decoding
│       │   ├── WhisperCppBackend.swift       # whisper.cpp sidecar integration
│       │   └── MLXWhisperBackend.swift       # MLX Whisper sidecar integration
│       └── Storage/
│           ├── Database.swift                # SQLite via GRDB, migrations
│           └── SettingsStore.swift            # Key-value settings CRUD
├── Tests/
│   └── VoxOpsCoreTests/
│       ├── AudioBufferTests.swift            # WAV export, duration, properties
│       ├── ClipboardInjectorTests.swift      # AppleScript generation
│       ├── DatabaseTests.swift               # Migration verification
│       ├── PipelineIntegrationTests.swift    # End-to-end with mock STT
│       ├── RawFormatterTests.swift           # Text cleanup rules
│       ├── SettingsStoreTests.swift          # CRUD round-trips
│       ├── SidecarProcessTests.swift         # Process stdin/stdout I/O
│       ├── TranscriptResultTests.swift       # JSON decoding
│       └── WhisperCppBackendTests.swift      # Backend identity + status
├── VoxOpsApp/
│   ├── VoxOpsApp.swift                       # @main — MenuBarExtra + Settings
│   ├── AppState.swift                        # Pipeline orchestrator
│   ├── Info.plist                            # LSUIElement, mic permission
│   ├── VoxOpsApp.entitlements                # Sandbox disabled, audio input
│   └── Views/
│       ├── HUDWindow.swift                   # NSPanel — nonactivating, floating
│       ├── HUDOrbView.swift                  # SwiftUI orb with animations
│       ├── MenuBarView.swift                 # Menu bar dropdown
│       └── SettingsView.swift                # Hotkey, backend, audio config
├── Scripts/
│   ├── whisper-sidecar/
│   │   ├── run.sh                            # Bash wrapper: WAV path → JSON
│   │   └── README.md                         # Setup + model download
│   └── mlx-whisper-sidecar/
│       ├── server.py                         # Unix socket server
│       ├── requirements.txt                  # mlx-whisper, numpy
│       └── README.md                         # Setup instructions
└── docs/
    └── superpowers/
        ├── specs/
        │   └── 2026-04-05-voxops-design.md   # Full design specification
        └── plans/
            └── 2026-04-05-voxops-v1-core-dictation.md  # V1 implementation plan
```

## Quick Start

### Prerequisites

- macOS 14.0+ (Sonoma or later)
- Apple Silicon Mac (M1+)
- Xcode 15.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

### Build

```bash
# Clone the repo
git clone https://github.com/EricGrill/vox-ops.git
cd vox-ops

# Build core library (SPM)
swift build

# Run tests
swift test

# Generate Xcode project
xcodegen generate

# Build the app
xcodebuild -project VoxOps.xcodeproj -scheme VoxOpsApp -configuration Debug build
```

### Download a Whisper Model

```bash
# Create model directory
mkdir -p ~/Library/Application\ Support/VoxOps/Models

# Download Whisper small model (~500MB)
curl -L -o ~/Library/Application\ Support/VoxOps/Models/ggml-small.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
```

### Install whisper.cpp (for whisper.cpp backend)

```bash
brew install whisper-cpp
```

### Install MLX Whisper (for MLX backend)

```bash
cd Scripts/mlx-whisper-sidecar
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Grant Permissions

VoxOps requires two macOS permissions:

1. **Accessibility** — System Settings → Privacy & Security → Accessibility → Add VoxOps
2. **Microphone** — Prompted on first launch

### Run

Open `VoxOps.xcodeproj` in Xcode and run the `VoxOpsApp` scheme, or build and run from the command line. The app appears as a menu bar icon (no Dock icon).

**Default hotkey:** Right Option (`⌥`)

Hold → speak → release → text appears at your cursor.

## Storage

| Store | Location | Purpose |
|-------|----------|---------|
| **SQLite** | `~/Library/Application Support/VoxOps/voxops.sqlite` | Settings, profiles, history, audit log |
| **Keychain** | macOS Keychain | API credentials for adapters and remote STT |
| **Models** | `~/Library/Application Support/VoxOps/Models/` | Whisper model files (.bin) |

## Privacy

- **Local-first** — no cloud dependency by default
- **Audio is ephemeral** — buffer discarded after STT returns transcript
- **History is opt-in** — stores transcript + mode + result, never raw audio
- **No telemetry** — no phone-home, no analytics unless user opts in
- **Remote STT** — requires explicit opt-in + first-time confirmation dialog

## Test Coverage

```
27 tests across 9 suites — all passing

Suite                    Tests   Coverage
─────────────────────────────────────────
AudioBuffer                 3   WAV export, duration, properties
ClipboardInjector           2   AppleScript generation, escaping
Database                    1   Migration verification
PipelineIntegration         2   End-to-end mock, WAV round-trip
RawFormatter                8   Capitalization, punctuation, spacing
SettingsStore               3   Nil default, round-trip, overwrite
SidecarProcess              3   Launch, stop, stdin/stdout I/O
TranscriptResult            3   Creation, empty, JSON decode
WhisperCppBackend           2   Identity, initial status
```

## Release Plan

| Version | Scope | Status |
|---------|-------|--------|
| **V1** | Core dictation — hotkey, STT, raw mode, text injection, HUD, menu bar | ✅ Built |
| **V2** | Prompt + command modes, intent router, app-aware profiles | Planned |
| **V3** | Agent adapter integration, dispatch status, command schemas | Planned |
| **V4** | System mode, workflow registry, history panel, custom grammars | Planned |

## Tech Stack

| Component | Technology |
|-----------|-----------|
| App framework | Swift 5.9+, SwiftUI |
| Menu bar | `MenuBarExtra` |
| HUD | `NSPanel` (nonactivating) |
| Audio capture | AVFoundation / CoreAudio |
| Global hotkey | `CGEvent` tap |
| Text injection | Accessibility API (`AXUIElement`) |
| Local STT | whisper.cpp, MLX Whisper |
| Database | SQLite via [GRDB](https://github.com/groue/GRDB.swift) |
| Credentials | macOS Keychain |
| Build | Swift Package Manager + XcodeGen |

---

<p align="center">
  <i>Built for builders who'd rather speak than type.</i>
</p>
