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

## Install

```bash
brew tap EricGrill/tap
brew install --cask voxops
```

Or download the latest `.zip` from [GitHub Releases](https://github.com/EricGrill/vox-ops/releases), extract, and drag to Applications.

### Setup

1. **Download a Whisper model** (~500MB, runs locally):
   ```bash
   mkdir -p ~/Library/Application\ Support/VoxOps/Models
   curl -L -o ~/Library/Application\ Support/VoxOps/Models/ggml-small.bin \
     https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
   ```

2. **Install whisper.cpp:**
   ```bash
   brew install whisper-cpp
   ```

3. **Grant permissions** — on first launch macOS will prompt for:
   - **Accessibility** — System Settings → Privacy & Security → Accessibility → Add VoxOps
   - **Microphone** — Prompted automatically

4. **Launch** — VoxOps appears as a menu bar icon (no Dock icon).

**Default hotkey:** Hold → speak → release → text appears at your cursor.

### Agent Chat (Optional)

Connect to [OpenClaw](https://github.com/AiCrew/openclaw) or Hermes agent servers:

1. Open Settings → Agents → Add Server
2. Local servers are auto-discovered on localhost
3. OpenClaw tokens are auto-filled from `~/.openclaw/gateway-token`
4. Set a chat hotkey in Settings → Agents → Chat Hotkey
5. Press the chat hotkey to open the agent chat window

## Development

### Prerequisites

- macOS 14.0+ (Sonoma or later)
- Apple Silicon Mac (M1+)
- Xcode 15.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

### Build from Source

```bash
git clone https://github.com/EricGrill/vox-ops.git
cd vox-ops

swift build        # Build core library
swift test         # Run tests
xcodegen generate  # Generate Xcode project
xcodebuild -project VoxOps.xcodeproj -scheme VoxOpsApp -configuration Debug build
```

### MLX Whisper Backend (alternative)

```bash
cd Scripts/mlx-whisper-sidecar
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Releasing

```bash
# Tag triggers GitHub Actions → builds → creates release
git tag v0.2.0 && git push origin v0.2.0

# Or build locally
./Scripts/build-release.sh 0.2.0
```

After release, update the SHA256 and version in the [Homebrew cask](https://github.com/EricGrill/homebrew-tap/blob/main/Casks/voxops.rb).

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
86 tests across 20 suites — all passing
```

## Release Plan

| Version | Scope | Status |
|---------|-------|--------|
| **0.1.0** | Core dictation + agent chat integration (OpenClaw, Hermes) | ✅ Released |
| **V2** | Prompt + command modes, intent router, app-aware profiles | Planned |
| **V3** | Agent response routing to external channels | Planned |
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
