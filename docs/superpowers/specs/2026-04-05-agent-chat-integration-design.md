# VoxOps Agent Chat Integration Design

**Date:** 2026-04-05
**Status:** Approved

## Overview

Integrate OpenClaw and Hermes agent backends into VoxOps, adding a configurable agent chat window accessible via hotkey. Users configure one or more agent servers (OpenClaw or Hermes instances), each hosting one or more agents. A tabbed chat window provides direct conversation with any enabled agent.

Additionally: remove mouse button bindings from HotkeyManager (Logitech software handles mouse→key mapping externally) and add a second configurable hotkey for the chat window.

## Architecture

### Unified Agent Client Protocol

A Swift protocol abstracts over both backends so the chat window and settings UI are backend-agnostic.

```swift
protocol AgentClient {
    var serverId: UUID { get }
    var serverType: ServerType { get }

    func connect() async throws
    func disconnect() async
    func listAgents() async throws -> [AgentProfile]
    func send(messages: [ChatMessage], agentId: String) -> AsyncThrowingStream<AgentEvent, Error>
    func healthCheck() async -> Bool
}

struct ChatMessage: Codable {
    enum Role: String, Codable { case user, assistant, system }
    let role: Role
    let content: String
}

enum ServerType: String, Codable {
    case openclaw
    case hermes
}

enum AgentEvent {
    case textChunk(String)      // streaming text fragment
    case error(String)          // agent-side error
    // Stream completion (AsyncThrowingStream finishes) signals the response is done.
    // The ChatViewModel assembles the full text from chunks.
}
```

### OpenClawClient (WebSocket)

- Connects to `ws://host:port`, sends `connect` frame with token for auth
- `listAgents()` sends `agents.list` frame, returns discovered `AgentProfile` entries
- `send()` sends `agent` frame with `agentId` and `idempotencyKey`, yields `AgentEvent` from streamed event frames (`type: "event"`, `event: "agent"`). Only the latest user message is sent — OpenClaw manages conversation history server-side via sessions.
- Maintains persistent WebSocket connection via `URLSessionWebSocketTask` (macOS 14+). Auto-reconnect on drop with exponential backoff (1s, 2s, 4s, 8s max), jitter, and max 5 retries before surfacing error to UI. In-flight requests are not replayed — the user re-sends if needed.

**OpenClaw frame protocol:**

```json
// Request
{ "type": "req", "id": "uuid", "method": "agent", "params": {
    "message": "Hello", "agentId": "default", "idempotencyKey": "uuid"
}}

// Response (initial)
{ "type": "res", "id": "uuid", "ok": true, "payload": { "runId": "xyz" } }

// Streamed events
{ "type": "event", "event": "agent", "payload": {
    "runId": "xyz", "type": "text", "text": "...", "done": false
}}
```

### HermesClient (HTTP/SSE)

- No persistent connection
- `listAgents()` returns a single hardcoded agent (Hermes is one-agent-per-endpoint)
- `send()` POSTs to `/v1/chat/completions` with `stream: true` and the full `[ChatMessage]` array (Hermes API is stateless — client must send conversation history). Parses SSE `data:` lines, extracts `choices[0].delta.content`, yields as `AgentEvent.textChunk`. Handles `data: [DONE]` sentinel. SSE parser implemented inline (~50 lines using `URLSession.bytes`).
- Auth via `Authorization: Bearer {token}` header
- Cancellation: dropping the `AsyncThrowingStream` consumer cancels the underlying `URLSession` data task via Swift structured concurrency.

### AgentClientManager

Owns all `AgentClient` instances. Runs on `@MainActor` for thread safety with UI updates. Responsibilities:

- Initializes clients from stored `AgentServer` configs on app launch
- Provides `func client(for serverId: UUID) -> AgentClient?`
- Handles connect/disconnect lifecycle on settings change
- Exposes combined agent list across all servers for the chat UI
- Refreshes agent discovery on launch and on user request

## Data Model

### AgentServer

```swift
struct AgentServer: Codable, Identifiable {
    let id: UUID
    var name: String
    var type: ServerType
    var url: String           // ws:// for OpenClaw, http:// for Hermes
    var enabled: Bool
    // Auth token stored in Keychain keyed by "voxops.agent.{id}"
}
```

### AgentProfile

```swift
struct AgentProfile: Codable, Identifiable {
    let id: String            // agent ID from server (e.g. "default", "darth")
    let serverId: UUID
    var name: String
    var enabled: Bool
}
```

### Settings Storage

- `agent_servers` — JSON array of `AgentServer` in SQLite settings store
- `hotkey_trigger` — voice push-to-talk (existing)
- `hotkey_chat_trigger` — agent chat window hotkey (new)
- Auth tokens in Keychain keyed by `voxops.agent.{serverId}`
- Agent profiles cached in-memory, refreshed from servers on connect. Agent `enabled` state persisted in `agent_profiles` settings key so disabled agents stay hidden across restarts.

## HotkeyManager Changes

### Remove Mouse Button Support

`HotkeyTrigger` simplifies from enum to struct (keyboard-only):

```swift
struct HotkeyTrigger: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: Set<ModifierKey>
}
```

Remove from `HotkeyManager`:
- `otherMouseDown` / `otherMouseUp` event handling
- `.mouseButton` case and all mouse-related CGEvent types
- Mouse button validation in `HotkeyTrigger.validate()`

Logitech software (or similar) handles mouse button → keyboard shortcut mapping externally.

**Migration:** Existing users who stored a `.mouseButton` trigger will hit a decode failure since the enum case no longer exists. The existing fallback in `AppState.loadSettings()` silently defaults to ⌘Space on decode failure — this is the intended migration path. No explicit data migration needed.

### Second Hotkey for Chat Window

Two configurable triggers:
- `hotkey_trigger` — push-to-talk voice input (default: ⌘Space)
- `hotkey_chat_trigger` — toggle agent chat window (default: ⇧⌘Space)

`HotkeyManager` callbacks:
- `onKeyDown` / `onKeyUp` — voice push-to-talk (hold to record, release to send)
- `onChatToggle` — single keyDown of chat hotkey toggles the chat window

**Single event tap, dual dispatch:** One `HotkeyManager` instance owns one CGEvent tap. The tap handler checks incoming events against both triggers and dispatches to the appropriate callback. The manager tracks two independent activation states (`isVoiceActive`, `isChatActive`). This avoids the overhead and ordering issues of running two separate event taps.

**Hotkey collision validation:** `AppState` validates that voice and chat triggers are not identical when saving either one. If they match, the save is rejected with an error shown in settings.

### Push-to-Talk Verification

The existing implementation uses `CGEvent` tap with `keyDown` → `keyUp` detection. Verify:
- Auto-repeat events are filtered (no duplicate keyDown on held keys)
- `flagsChanged` events correctly detect modifier release (existing logic)
- Clean separation between voice hotkey hold and chat hotkey single-press

## Chat Window UI

### Window

`NSPanel` with `becomesKeyOnlyIfNeeded = true`. Unlike the HUD (which is display-only and non-activating), the chat window needs keyboard focus for text input. The panel becomes key window when the user interacts with the text field but does not activate the app (no Dock bounce, no menu bar takeover). Toggled visible/hidden by chat hotkey. Remembers position/size between toggles, resets on app restart.

### Layout

```
┌─────────────────────────────────────────┐
│ [Agent A] [Agent B] [Agent C]    [gear] │  tab bar + settings shortcut
├─────────────────────────────────────────┤
│                                         │
│  Agent messages left-aligned            │
│  User messages right-aligned            │
│  Streaming responses render in          │
│  real-time as chunks arrive             │
│                                         │
├─────────────────────────────────────────┤
│ [message input field]          [send ↩] │  text input + send
└─────────────────────────────────────────┘
```

### Behavior

- Tabs auto-populated from all enabled agents across all servers
- Tab labels show agent name + server name if ambiguous (e.g., "Darth (Local)" vs "Darth (Prod)")
- Each tab maintains its own conversation history in-memory (not persisted across restarts)
- Streaming text chunks append to agent message bubble in real-time
- Enter submits message, Shift+Enter inserts newline
- No voice input in chat window (push-to-talk handles that separately)
- Connection status shown per-tab (●connected / ○disconnected / ◌reconnecting)

### SwiftUI Architecture

- `ChatWindowController` — `NSPanel` wrapper (pattern from existing `HUDWindow`)
- `ChatView` — SwiftUI view with `TabView` and message list
- `ChatViewModel` — `@Observable` per-tab state, drives `AgentClient.send()` async stream. Runs on `@MainActor`. Cancels in-flight request Task when user sends a new message or switches tabs.

## Settings UI

### New "Agents" Tab

Added alongside existing General and Audio tabs.

**Server list** with connected/disconnected indicators (●/○), edit and delete buttons, and "Add Server" button.

**Add/Edit Server sheet:**
- Name, Type (dropdown: OpenClaw/Hermes), URL, Token fields
- Type selection changes URL placeholder (ws:// vs http://)
- Auto-discovered agent list with enable/disable checkboxes
- "Refresh Agents" button to re-discover
- "Test Connection" button verifies connectivity and auth
- Token stored in Keychain on save

**Chat Hotkey** recorder using existing `KeyboardRecorderView` component.

## File Structure

### New Files

```
Sources/VoxOpsCore/
  Agent/
    AgentClient.swift          — protocol, AgentEvent, ServerType
    OpenClawClient.swift       — WebSocket implementation
    HermesClient.swift         — HTTP/SSE implementation
    AgentClientManager.swift   — lifecycle, combined agent list
    AgentServer.swift          — server config model
    AgentProfile.swift         — agent profile model

VoxOpsApp/
  Views/
    ChatWindow.swift           — NSPanel wrapper
    ChatView.swift             — SwiftUI tabbed chat UI
    ChatViewModel.swift        — per-tab conversation state
    AgentSettingsView.swift    — Agents tab in settings
    ServerFormView.swift       — Add/edit server sheet
```

### Modified Files

```
Sources/VoxOpsCore/
  Hotkey/HotkeyManager.swift   — remove mouse support, add onChatToggle
  Hotkey/HotkeyTrigger.swift   — remove .mouseButton, simplify to struct
  Storage/Database.swift        — migration for new settings keys

VoxOpsApp/
  AppState.swift               — init AgentClientManager, wire chat hotkey
  Views/SettingsView.swift     — add Agents tab
```

## Testing

- `AgentClientTests` — mock WebSocket/HTTP to test protocol conformance, streaming, reconnection
- `OpenClawClientTests` — frame serialization, `agents.list` parsing, event stream handling
- `HermesClientTests` — SSE parsing, auth header, request format
- `HotkeyTriggerTests` — update existing tests: remove mouse cases, verify keyboard-only
- `AgentClientManagerTests` — multi-server lifecycle, agent discovery aggregation

No integration tests against real servers — manual verification only.
