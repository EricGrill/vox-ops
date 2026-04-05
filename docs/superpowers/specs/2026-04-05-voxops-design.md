# VoxOps — Design Specification

**Date:** 2026-04-05
**Status:** Draft
**Tagline:** Push-to-talk voice → structured action → agent execution.

---

## 1. Overview

VoxOps is a native macOS push-to-talk voice input and execution layer for technical users. It combines low-latency local speech-to-text with structured output modes, app-aware text injection, and a generic agent dispatch system. Built in Swift + SwiftUI, targeting Apple Silicon.

### Core Interaction

1. User holds a hotkey
2. Speaks naturally
3. Releases
4. Text appears at cursor, command executes, or agent job is dispatched

### Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Platform | Native Swift + SwiftUI | Best macOS integration, performance, and Accessibility API access |
| Architecture | Core App + Sidecar Processes | Process isolation for STT engines, native speed for hot path |
| STT Backends | whisper.cpp + MLX Whisper (abstracted) | Flexibility — C++ for embedding, Python for MLX ecosystem |
| Text Injection | Accessibility API primary, clipboard fallback | Most reliable direct insertion, universal fallback |
| Intent Parsing | Rule-based with optional LLM refinement | Fast, deterministic, predictable — LLM slots in later |
| Agent Integration | Generic adapter protocol | Works with any system via pluggable connectors |
| Profiles | Smart presets + full customization | Sensible defaults, power when needed |
| HUD | Orb default, expandable to transcript panel | Minimal when you want flow, detailed when you need visibility |

---

## 2. System Architecture

### Core App + Sidecar Processes

The system splits into two layers:

**Swift Core App (single process)** — owns everything on the latency-critical path:
- HotkeyManager
- AudioManager
- IntentRouter
- Formatter/Parser
- InjectionLayer
- ProfileManager
- AgentAdapter registry
- UI (MenuBarExtra + HUD)
- Storage (SQLite + Keychain)

**Sidecar Processes (managed lifecycle):**
- whisper.cpp — compiled C++ CLI
- MLX Whisper — Python process

Communication between core app and sidecars happens over Unix domain sockets (MLX Whisper) or stdin/stdout (whisper.cpp).

### Data Flow — Hot Path

1. Key down → HotkeyManager starts AudioManager recording
2. Key up → AudioManager stops, sends buffer to STT sidecar
3. STT returns transcript (< 500ms target for short utterances)
4. IntentRouter classifies: raw | prompt | command | agent | system
5. Formatter/Parser transforms per mode + active profile
6. InjectionLayer inserts at cursor (AX API) or dispatches via adapter
7. HUD shows success/error

### Performance Targets

| Metric | Target |
|--------|--------|
| Hotkey response latency | < 50ms |
| Transcript ready (short utterance) | < 500ms |
| Text insertion after transcript | < 150ms |
| Command parse time (local) | < 700ms |
| Command parse time (remote) | < 1500ms |

---

## 3. Component Design

### 3.1 HotkeyManager

Captures global push-to-talk input using a CGEvent tap. Configurable hotkey (default: user-selected during onboarding). Fires `keyDown` → start recording and `keyUp` → stop recording events to the AudioManager.

Supports:
- Single configurable hotkey for push-to-talk
- Mode-switch hotkeys (⌘1-5 for switching between modes)
- Optional sound cues for start/stop/complete

### 3.2 AudioManager

Records microphone audio using AVFoundation/CoreAudio.

Responsibilities:
- Start/stop recording on HotkeyManager events
- Manage microphone selection (list available, switch, remember preference)
- Produce audio buffer in format expected by STT backends (16kHz mono WAV)
- Optional noise gate / voice activity detection tuning
- Buffer is ephemeral — discarded after STT returns transcript

### 3.3 STT Engine Layer

Abstracted behind a Swift protocol. Both backends are first-class:

```swift
protocol STTBackend {
    var id: String { get }
    var status: BackendStatus { get }
    func transcribe(audio: AudioBuffer) async throws -> TranscriptResult
    func streamingTranscribe(audio: AudioBuffer) -> AsyncStream<PartialTranscript>
}
```

**whisper.cpp sidecar:**
- Long-running CLI process
- Core app writes WAV audio to temp file, passes path via stdin
- Reads JSON transcript response on stdout

**MLX Whisper sidecar:**
- Python process on Unix domain socket
- Core app connects, sends audio buffer
- Receives streaming partial transcripts followed by final result
- Socket path in app's temp directory

**Lifecycle Management:**
- Lazy-started on first use (not at app launch)
- Crash detection via process termination signal
- Restart on next request (not eagerly, to avoid crash loops)
- Terminated via SIGTERM with grace period on app quit

**Model Management:**
- Models stored in `~/Library/Application Support/VoxOps/Models/`
- Settings UI: available models, download status, disk size
- First launch prompts download of default model
- Custom models supported via file path

**Backend Selection:**
- Global default in Settings
- Per-profile override available
- Auto mode: prefer MLX Whisper on Apple Silicon with sufficient RAM, fall back to whisper.cpp

### 3.4 IntentRouter

Decides which output mode to apply to a transcript.

**Routing Logic (in order):**
1. Check for explicit spoken prefixes ("command:", "agent:", "run:") — deterministic routing
2. Check active mode override (user locked a mode via hotkey or menu)
3. If auto-detect is on: run rule-based classifier (keyword patterns, confidence score). Below threshold → raw mode fallback.
4. Future: optional local LLM classifier slot behind the same interface

Produces a `RoutingDecision`:
- Selected mode
- Confidence score
- Original transcript
- Matching rule (for debugging/logging)

### 3.5 Formatter / Parser

Per-mode transformation pipelines:

**Raw Mode:** Minimal cleanup — capitalization, basic punctuation. No LLM. Fastest path.

**Prompt Mode:** Grammar cleanup, filler word removal, sentence restructuring. Rule-based by default, optional LLM for heavier reformatting. Supports custom prompt templates per profile.

**Command Mode:** Matches transcript against registered command schemas (verb + noun + params pattern). Outputs structured JSON:
```json
{
  "action": "create_prd",
  "topic": "agent-driven video pipeline",
  "assign_to": "builder_agent",
  "confidence": 0.92
}
```
Schemas are user-definable. Unmatched utterances fall back to raw mode with confidence warning.

**Agent Mode:** Same parsing as Command Mode, but output is routed to an agent adapter instead of injected as text.

**System Mode:** Same parsing as Command Mode, but output is matched against the workflow registry for local execution.

### 3.6 InjectionLayer

Inserts text into the active application.

**Primary — Accessibility API (AXUIElement):**
- Query focused app → get focused element → check AXValue support → set value
- For elements supporting AXSelectedTextRange, insert at cursor position
- Handles most native macOS apps

**Fallback — Clipboard Paste:**
- Save current clipboard → set to output text → simulate Cmd+V → restore clipboard after delay
- Works everywhere, briefly clobbers clipboard

**Per-App Overrides (via Profiles):**
- Injection strategy per app bundle ID: `ax`, `clipboard`, `keystroke`
- Ships with defaults for: Terminal.app, iTerm2, VS Code, Cursor, Slack, Arc, Safari

**Formatting Rules (profile-driven):**
- `smartPunctuation`: on/off
- `preserveSymbols`: on/off
- `grammarCleanup`: on/off
- `stripFillers`: on/off
- `caseStyle`: natural | lowercase | UPPERCASE | preserve

**Focus Management:**
- HUD is a non-activating NSPanel — never steals focus
- After injection, cursor positioned at end of inserted text

### 3.7 Agent Adapter System

Generic protocol for routing commands to external systems:

```swift
protocol AgentAdapter {
    var id: String { get }
    var displayName: String { get }
    func send(command: StructuredCommand) async throws -> DispatchResult
    func healthCheck() async -> AdapterStatus
}
```

`StructuredCommand` carries: action, parameters, metadata, confidence score, original transcript.
`DispatchResult` carries: success/failure, summary string for HUD, optional response data.

**Built-in Adapters:**
- **GenericREST** — configurable URL, method, headers, auth (Bearer/API key). User defines field mapping.
- **GenericWebSocket** — persistent socket, JSON messages, reconnection support.

**Configuration:**
- Each adapter instance: name, type, endpoint, auth (Keychain), optional command filter
- Multiple instances can coexist — router matches by command schema
- Configured via Settings UI or JSON config file

**Dispatch Flow:**
1. Command/Agent Mode produces StructuredCommand
2. Router matches against adapter filters
3. Adapter sends, awaits response
4. HUD shows status: sending → success/error with summary
5. Audit log records attempt

### 3.8 Profile System

Profiles are configuration bundles keyed to app bundle IDs or user-defined names.

**Profile Properties:**
- Default mode (raw, prompt, command, agent, system)
- STT backend (specific or "auto")
- Formatting rules (smartPunctuation, preserveSymbols, grammarCleanup, stripFillers, caseStyle)
- Injection strategy (ax, clipboard, keystroke, auto)
- Custom prompt templates per mode

**Built-in Presets:**
- `terminal` — raw mode, no smart punctuation, preserve symbols, clipboard injection
- `editor` — prompt mode, preserve symbols, AX injection
- `chat` — raw mode, smart punctuation, grammar cleanup, AX injection
- `default` — raw mode, light cleanup, auto injection

**Auto-Detection:**
- On each hotkey press, read frontmost app bundle ID via NSWorkspace
- Match: exact → custom override → preset → default
- Active profile shown in HUD and menu bar

**Customization:**
- Stored in SQLite, editable via Settings UI
- Export/import as JSON
- Clone preset and customize
- Future: profile inheritance

### 3.9 UI Layer

**Floating HUD Orb:**
- NSPanel with `.nonactivatingPanel` style
- User-draggable, remembers position
- Visual states:
  - Idle — dim gray dot
  - Listening — pulsing red glow
  - Processing — amber with spinning ring
  - Success — green flash, fades to idle (~1s)
  - Error — red shake, tooltip with error message

**Expanded Panel (hover or verbose mode):**
- Live transcript as words arrive (streaming partials)
- Active mode, backend, latency, target app
- Injection method used
- Always-on option via verbose mode setting

**Menu Bar (MenuBarExtra):**
- Icon color matches orb states
- Dropdown: current mode (⌘1-5), active profile, backend
- Quick access to History and Settings

**Settings Window (SwiftUI):**
- Hotkey configuration
- Mode defaults and auto-detect toggle
- STT backend selection and model management
- Profile editor (presets + custom)
- Agent adapter configuration
- Audio settings (mic, noise gate)
- Privacy controls

### 3.10 Storage

**SQLite** — single database in Application Support:
- Settings table
- Profiles table
- History table (opt-in: transcript, mode, result, timestamp)
- Audit log table (always on: action type, command, adapter, result, latency, timestamp)
- Command schemas table
- Workflow registry table

**Keychain** — API credentials for agent adapters and remote STT providers.

---

## 4. Command Execution Safety

### System Mode Workflow Registry

Approved workflows defined in a JSON registry file in app support directory:
- Entry: name, description, shell command/script path, `destructive` flag, confirmation level
- Confirmation levels: `none` (safe), `confirm` (requires user approval), `deny` (blocked)

### Safety Layers

1. **Parse** — utterance must match a registered workflow. Unrecognized commands never execute.
2. **Classify** — matched workflow checked for destructive flag
3. **Gate** — destructive workflows show confirmation in HUD with exact command. Confirm hotkey or click required. Timeout = deny.
4. **Execute** — sandboxed via Swift `Process`, stdout/stderr captured, timeout enforced
5. **Log** — every attempt written to audit log

### Privacy Controls

- Audio ephemeral by default — buffer discarded after STT
- History opt-in — stores transcript + mode + result, never raw audio
- Redaction rules: user-defined regex patterns, matched strings → `[REDACTED]` before storage
- Remote STT requires explicit opt-in + first-time confirmation
- No telemetry, no phone-home, no analytics unless user opts in

---

## 5. Output Modes Summary

| Mode | Input | Transform | Output | Destination |
|------|-------|-----------|--------|-------------|
| Raw | transcript | minimal cleanup | text | cursor injection |
| Prompt | transcript | grammar/filler cleanup + template | text | cursor injection |
| Command | transcript | schema matching | JSON | cursor injection |
| Agent | transcript | schema matching | JSON | agent adapter |
| System | transcript | workflow matching | shell command | local execution |

---

## 6. Release Plan

### V1: Core Dictation Engine
- Global hotkey (CGEvent tap)
- Audio capture (AVFoundation)
- Local STT (whisper.cpp + MLX Whisper sidecars)
- Raw mode with minimal text cleanup
- Text injection (AX API + clipboard fallback)
- Floating HUD orb with visual states
- Menu bar app (MenuBarExtra)
- Basic settings (hotkey, mic, model download)
- SQLite storage for settings

### V2: Prompt and Command Layer
- Prompt mode with rule-based transforms
- Command mode with schema matching + JSON output
- Intent router with spoken prefixes and rule-based classification
- Confidence fallback to raw mode
- Per-app formatting rules (terminal, editor, chat presets)
- Profile auto-detection by bundle ID

### V3: Agent Integration
- Agent adapter protocol + built-in REST/WebSocket adapters
- Agent mode routing
- Dispatch status in HUD
- User-definable command schemas
- Adapter configuration in Settings
- Audit logging

### V4: Advanced Power Features
- Full profile editor with custom rules
- System mode with workflow registry + safety gates
- History panel with search and replay
- Expanded HUD panel with live transcript
- Custom prompt templates per profile
- Export/import profiles as JSON
- Optional sound cues
- Redaction rules for privacy

---

## 7. Open Questions

1. Should command parsing allow regex/rule-based first-pass parsing before any LLM involvement? **Decision: Yes — rule-based first, LLM optional refinement.**
2. Should agent dispatch results come back visually or via TTS? **Deferred to V4+.**
3. How aggressive should terminal-safe formatting be? **Handled via profile presets — user can tune.**
4. Should spoken prefixes ("command:", "agent:") be used in V1/V2? **Decision: Yes, as deterministic routing triggers.**
5. Should system mode use a fixed workflow registry? **Decision: Yes — allowlisted workflows only, no free-form shell translation.**
