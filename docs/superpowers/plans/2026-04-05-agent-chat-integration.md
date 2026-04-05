# Agent Chat Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate OpenClaw and Hermes agent backends into VoxOps with a tabbed chat window, unified agent protocol, settings UI, and dual-hotkey support.

**Architecture:** Unified `AgentClient` protocol abstracts over OpenClaw (WebSocket) and Hermes (HTTP/SSE). `AgentClientManager` owns all client instances. A floating `NSPanel` chat window with tabbed agent conversations is toggled by a second configurable hotkey. `HotkeyManager` handles both hotkeys via a single CGEvent tap.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (NSPanel), URLSession (WebSocket + SSE), GRDB (settings), Keychain (auth tokens)

**Spec:** `docs/superpowers/specs/2026-04-05-agent-chat-integration-design.md`

---

## File Structure

### New Files (VoxOpsCore)

| File | Responsibility |
|------|---------------|
| `Sources/VoxOpsCore/Agent/AgentClient.swift` | Protocol, `ChatMessage`, `AgentEvent`, `ServerType` |
| `Sources/VoxOpsCore/Agent/AgentServer.swift` | Server config model |
| `Sources/VoxOpsCore/Agent/AgentProfile.swift` | Agent profile model |
| `Sources/VoxOpsCore/Agent/OpenClawClient.swift` | WebSocket client for OpenClaw |
| `Sources/VoxOpsCore/Agent/HermesClient.swift` | HTTP/SSE client for Hermes |
| `Sources/VoxOpsCore/Agent/AgentClientManager.swift` | Lifecycle, combined agent list |
| `Sources/VoxOpsCore/Storage/KeychainStore.swift` | Keychain read/write for auth tokens |

### New Files (App)

| File | Responsibility |
|------|---------------|
| `VoxOpsApp/Views/ChatWindow.swift` | NSPanel wrapper for chat |
| `VoxOpsApp/Views/ChatView.swift` | SwiftUI tabbed chat UI |
| `VoxOpsApp/Views/ChatViewModel.swift` | Per-tab conversation state |
| `VoxOpsApp/Views/AgentSettingsView.swift` | Agents tab in settings |
| `VoxOpsApp/Views/ServerFormView.swift` | Add/edit server sheet |

### New Test Files

| File | Tests |
|------|-------|
| `Tests/VoxOpsCoreTests/AgentClientTests.swift` | Protocol types, ChatMessage, AgentEvent |
| `Tests/VoxOpsCoreTests/AgentServerTests.swift` | Server/profile model serialization |
| `Tests/VoxOpsCoreTests/OpenClawClientTests.swift` | Frame serialization, event parsing |
| `Tests/VoxOpsCoreTests/HermesClientTests.swift` | SSE parsing, request format |
| `Tests/VoxOpsCoreTests/AgentClientManagerTests.swift` | Multi-server lifecycle |
| `Tests/VoxOpsCoreTests/KeychainStoreTests.swift` | Keychain read/write/delete |

### Modified Files

| File | Changes |
|------|---------|
| `Sources/VoxOpsCore/Hotkey/HotkeyTrigger.swift` | Remove `.mouseButton`, simplify to keyboard-only struct |
| `Sources/VoxOpsCore/Hotkey/HotkeyManager.swift` | Remove mouse handling, add dual-hotkey dispatch |
| `Tests/VoxOpsCoreTests/HotkeyTriggerTests.swift` | Remove mouse tests, add struct-based tests |
| `VoxOpsApp/AppState.swift` | Add AgentClientManager, chat hotkey, chat window |
| `VoxOpsApp/Views/SettingsView.swift` | Remove mouse picker, add Agents tab |

**Note:** `Database.swift` is NOT modified. New agent settings (`agent_servers`, `hotkey_chat_trigger`) are stored as JSON strings in the existing `settings` key-value table — no schema migration needed.

**Note on `HotkeyTrigger.modifiers`:** The plan uses `[ModifierKey]` (Array) not `Set<ModifierKey>` as the spec states. This is deliberate — the existing codebase uses arrays for deterministic JSON encoding order. The `init` sorts modifiers to ensure consistency.

---

## Task 1: Simplify HotkeyTrigger — Remove Mouse Support

**Files:**
- Modify: `Sources/VoxOpsCore/Hotkey/HotkeyTrigger.swift`
- Modify: `Tests/VoxOpsCoreTests/HotkeyTriggerTests.swift`

- [ ] **Step 1: Update tests — remove mouse tests, add struct-based tests**

Replace the entire test file. The trigger is now a struct with `keyCode` and `modifiers` (no more enum cases).

```swift
// Tests/VoxOpsCoreTests/HotkeyTriggerTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import VoxOpsCore

@Suite("HotkeyTrigger")
struct HotkeyTriggerTests {
    @Test("keyboard trigger JSON round-trip")
    func keyboardRoundTrip() throws {
        let trigger = HotkeyTrigger(keyCode: 0x31, modifiers: [.command, .option])
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(HotkeyTrigger.self, from: data)
        #expect(decoded == trigger)
    }

    @Test("modifiers encode in sorted order")
    func sortedModifiers() throws {
        let trigger = HotkeyTrigger(keyCode: 0x31, modifiers: [.shift, .command, .option])
        let data = try JSONEncoder().encode(trigger)
        let json = String(data: data, encoding: .utf8)!
        let commandIdx = json.range(of: "command")!.lowerBound
        let optionIdx = json.range(of: "option")!.lowerBound
        let shiftIdx = json.range(of: "shift")!.lowerBound
        #expect(commandIdx < optionIdx)
        #expect(optionIdx < shiftIdx)
    }

    @Test("default trigger is command-space")
    func defaultTrigger() {
        let trigger = HotkeyTrigger.default
        #expect(trigger.keyCode == 0x31)
        #expect(trigger.modifiers == [.command])
    }

    @Test("display string shows modifier symbols + key name")
    func displayString() {
        let trigger = HotkeyTrigger(keyCode: 0x31, modifiers: [.command, .option])
        #expect(trigger.displayString == "⌥⌘Space")
    }

    @Test("modifier key maps to correct CGEventFlags")
    func modifierMapping() {
        #expect(ModifierKey.command.cgEventFlag == .maskCommand)
        #expect(ModifierKey.option.cgEventFlag == .maskAlternate)
        #expect(ModifierKey.control.cgEventFlag == .maskControl)
        #expect(ModifierKey.shift.cgEventFlag == .maskShift)
    }

    @Test("cgEventFlags combines all modifiers")
    func combinedFlags() {
        let trigger = HotkeyTrigger(keyCode: 0x31, modifiers: [.command, .option])
        let flags = trigger.cgEventFlags
        #expect(flags.contains(.maskCommand))
        #expect(flags.contains(.maskAlternate))
    }

    @Test("validation rejects no modifiers")
    func rejectsNoModifiers() {
        let trigger = HotkeyTrigger(keyCode: 0x31, modifiers: [])
        #expect(trigger.validate() != nil)
    }

    @Test("validation rejects reserved shortcut cmd-Q")
    func rejectsReserved() {
        let trigger = HotkeyTrigger(keyCode: 0x0C, modifiers: [.command])
        #expect(trigger.validate() != nil)
    }

    @Test("validation accepts valid trigger")
    func acceptsValid() {
        let trigger = HotkeyTrigger(keyCode: 0x31, modifiers: [.command, .option])
        #expect(trigger.validate() == nil)
    }

    @Test("decoding old mouseButton JSON falls back gracefully")
    func legacyMouseFallback() {
        // Old mouseButton payloads should fail to decode as HotkeyTrigger struct
        let mouseJSON = #"{"buttonNumber":4}"#
        let data = mouseJSON.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(HotkeyTrigger.self, from: data)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift test --filter HotkeyTriggerTests 2>&1 | tail -20`
Expected: Compilation errors — `HotkeyTrigger` is still an enum, not a struct with init.

- [ ] **Step 3: Rewrite HotkeyTrigger as keyboard-only struct**

Replace `Sources/VoxOpsCore/Hotkey/HotkeyTrigger.swift` entirely:

```swift
// Sources/VoxOpsCore/Hotkey/HotkeyTrigger.swift
import Foundation
import CoreGraphics

public enum ModifierKey: String, Codable, CaseIterable, Comparable, Sendable {
    case command, control, option, shift

    public var cgEventFlag: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .option:  return .maskAlternate
        case .control: return .maskControl
        case .shift:   return .maskShift
        }
    }

    public var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option:  return "⌥"
        case .shift:   return "⇧"
        case .command: return "⌘"
        }
    }

    public static func < (lhs: ModifierKey, rhs: ModifierKey) -> Bool {
        let order: [ModifierKey] = [.command, .control, .option, .shift]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }

    static let displayOrder: [ModifierKey] = [.control, .option, .shift, .command]

    var displaySortIndex: Int {
        Self.displayOrder.firstIndex(of: self)!
    }
}

public struct HotkeyTrigger: Codable, Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: [ModifierKey]

    public static let `default` = HotkeyTrigger(keyCode: 0x31, modifiers: [.command])

    public init(keyCode: UInt16, modifiers: [ModifierKey]) {
        self.keyCode = keyCode
        self.modifiers = modifiers.sorted()
    }

    public var cgEventFlags: CGEventFlags {
        var flags = CGEventFlags()
        for mod in modifiers { flags.insert(mod.cgEventFlag) }
        return flags
    }

    public var displayString: String {
        let modStr = modifiers.sorted(by: { $0.displaySortIndex < $1.displaySortIndex }).map(\.symbol).joined()
        let keyName = Self.keyCodeName(keyCode)
        return modStr + keyName
    }

    public func validate() -> String? {
        if modifiers.isEmpty { return "Keyboard shortcut requires at least one modifier" }
        if isReserved(keyCode: keyCode, modifiers: Set(modifiers)) {
            return "This shortcut is reserved by the system"
        }
        return nil
    }

    private static func keyCodeName(_ keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
            0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
            0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0",
            0x1E: "]", 0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I",
            0x23: "P", 0x24: "Return", 0x25: "L", 0x26: "J", 0x27: "'",
            0x28: "K", 0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/",
            0x2D: "N", 0x2E: "M", 0x2F: ".",
            0x30: "Tab", 0x31: "Space", 0x32: "`", 0x33: "Delete",
            0x35: "Escape",
            0x60: "F5", 0x61: "F6", 0x62: "F7", 0x63: "F3",
            0x64: "F8", 0x65: "F9", 0x67: "F11", 0x69: "F13",
            0x6B: "F14", 0x6D: "F10", 0x6F: "F12", 0x71: "F15",
            0x76: "F4", 0x78: "F2", 0x7A: "F1",
            0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        ]
        return names[keyCode] ?? "Key(\(keyCode))"
    }

    private func isReserved(keyCode: UInt16, modifiers: Set<ModifierKey>) -> Bool {
        let reserved: [(UInt16, Set<ModifierKey>)] = [
            (0x0C, [.command]),            // ⌘Q
            (0x0D, [.command]),            // ⌘W
            (0x30, [.command]),            // ⌘Tab
            (0x04, [.command]),            // ⌘H (Hide)
            (0x2E, [.command]),            // ⌘M (Minimize)
        ]
        return reserved.contains { $0.0 == keyCode && $0.1 == modifiers }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift test --filter HotkeyTriggerTests 2>&1 | tail -20`
Expected: All 10 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoxOpsCore/Hotkey/HotkeyTrigger.swift Tests/VoxOpsCoreTests/HotkeyTriggerTests.swift
git commit -m "refactor: simplify HotkeyTrigger to keyboard-only struct, remove mouse support"
```

---

## Task 2: Update HotkeyManager — Remove Mouse, Add Dual-Hotkey Dispatch

**Files:**
- Modify: `Sources/VoxOpsCore/Hotkey/HotkeyManager.swift`

- [ ] **Step 1: Rewrite HotkeyManager for dual-hotkey support**

Replace `Sources/VoxOpsCore/Hotkey/HotkeyManager.swift`:

```swift
// Sources/VoxOpsCore/Hotkey/HotkeyManager.swift
import Foundation
import CoreGraphics
import ApplicationServices

public final class HotkeyManager: @unchecked Sendable {
    public typealias KeyHandler = @Sendable () -> Void

    private let voiceTrigger: HotkeyTrigger
    private var chatTrigger: HotkeyTrigger?
    private var isVoiceActive = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retainedSelf: Unmanaged<HotkeyManager>?
    private let lock = NSLock()

    public var onKeyDown: KeyHandler?
    public var onKeyUp: KeyHandler?
    public var onChatToggle: KeyHandler?

    public init(voiceTrigger: HotkeyTrigger = .default, chatTrigger: HotkeyTrigger? = nil) {
        self.voiceTrigger = voiceTrigger
        self.chatTrigger = chatTrigger
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard AXIsProcessTrusted() else { throw HotkeyError.accessibilityNotGranted }

        let eventMask = (1 << CGEventType.keyDown.rawValue)
                      | (1 << CGEventType.keyUp.rawValue)
                      | (1 << CGEventType.flagsChanged.rawValue)

        let retained = Unmanaged.passRetained(self)
        self.retainedSelf = retained

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
            userInfo: retained.toOpaque()
        ) else {
            retained.release()
            self.retainedSelf = nil
            throw HotkeyError.cannotCreateEventTap
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    public func stop() {
        lock.lock()
        let wasActive = isVoiceActive
        let handler = wasActive ? onKeyUp : nil
        isVoiceActive = false
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        let retained = retainedSelf
        retainedSelf = nil
        lock.unlock()
        retained?.release()
        if wasActive { handler?() }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let mask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let activeModifiers = event.flags.intersection(mask)

        // Voice trigger: modifier release ends active session
        if isVoiceActive && type == .flagsChanged {
            if !activeModifiers.contains(voiceTrigger.cgEventFlags) {
                isVoiceActive = false
                onKeyUp?()
            }
            return Unmanaged.passUnretained(event)
        }

        // Chat trigger: single keyDown toggles chat window
        if let chat = chatTrigger, type == .keyDown, eventKeyCode == CGKeyCode(chat.keyCode) {
            if !chat.modifiers.isEmpty && !activeModifiers.contains(chat.cgEventFlags) {
                // Modifiers don't match — fall through
            } else if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                onChatToggle?()
                return nil // consume
            }
        }

        // Voice trigger: keyDown/keyUp for push-to-talk
        guard eventKeyCode == CGKeyCode(voiceTrigger.keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            if !voiceTrigger.modifiers.isEmpty {
                guard activeModifiers.contains(voiceTrigger.cgEventFlags) else {
                    return Unmanaged.passUnretained(event)
                }
            }
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                isVoiceActive = true
                onKeyDown?()
            }
            return nil // consume
        case .keyUp:
            guard isVoiceActive else { return Unmanaged.passUnretained(event) }
            isVoiceActive = false
            onKeyUp?()
            return nil // consume
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

- [ ] **Step 2: Verify existing tests still pass**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift test 2>&1 | tail -20`
Expected: All tests pass. `HotkeyManager` init changed from `init(trigger:)` to `init(voiceTrigger:chatTrigger:)` — this will cause compilation errors in `AppState.swift` but tests don't instantiate `AppState` directly.

- [ ] **Step 3: Commit**

```bash
git add Sources/VoxOpsCore/Hotkey/HotkeyManager.swift
git commit -m "refactor: HotkeyManager dual-hotkey dispatch, remove mouse event handling"
```

---

## Task 3: Agent Protocol Types — AgentClient, ChatMessage, Models

**Files:**
- Create: `Sources/VoxOpsCore/Agent/AgentClient.swift`
- Create: `Sources/VoxOpsCore/Agent/AgentServer.swift`
- Create: `Sources/VoxOpsCore/Agent/AgentProfile.swift`
- Create: `Tests/VoxOpsCoreTests/AgentClientTests.swift`
- Create: `Tests/VoxOpsCoreTests/AgentServerTests.swift`

- [ ] **Step 1: Write failing tests for protocol types**

```swift
// Tests/VoxOpsCoreTests/AgentClientTests.swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("AgentClient Protocol Types")
struct AgentClientTests {
    @Test("ChatMessage round-trips through JSON")
    func chatMessageRoundTrip() throws {
        let msg = ChatMessage(role: .user, content: "Hello agent")
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        #expect(decoded.role == .user)
        #expect(decoded.content == "Hello agent")
    }

    @Test("ChatMessage roles encode as strings")
    func chatMessageRoleEncoding() throws {
        let msg = ChatMessage(role: .assistant, content: "Hi")
        let data = try JSONEncoder().encode(msg)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"assistant\""))
    }

    @Test("ServerType round-trips through JSON")
    func serverTypeRoundTrip() throws {
        let types: [ServerType] = [.openclaw, .hermes]
        for type in types {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(ServerType.self, from: data)
            #expect(decoded == type)
        }
    }
}
```

```swift
// Tests/VoxOpsCoreTests/AgentServerTests.swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("AgentServer & AgentProfile Models")
struct AgentServerTests {
    @Test("AgentServer round-trips through JSON")
    func serverRoundTrip() throws {
        let server = AgentServer(
            id: UUID(),
            name: "Test OpenClaw",
            type: .openclaw,
            url: "ws://127.0.0.1:18789",
            enabled: true
        )
        let data = try JSONEncoder().encode(server)
        let decoded = try JSONDecoder().decode(AgentServer.self, from: data)
        #expect(decoded.id == server.id)
        #expect(decoded.name == "Test OpenClaw")
        #expect(decoded.type == .openclaw)
        #expect(decoded.url == "ws://127.0.0.1:18789")
        #expect(decoded.enabled == true)
    }

    @Test("AgentProfile round-trips through JSON")
    func profileRoundTrip() throws {
        let sid = UUID()
        let profile = AgentProfile(
            id: "darth",
            serverId: sid,
            name: "Darth",
            enabled: true
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(AgentProfile.self, from: data)
        #expect(decoded.agentId == "darth")
        #expect(decoded.id == "\(sid):darth")
        #expect(decoded.name == "Darth")
        #expect(decoded.enabled == true)
    }

    @Test("AgentServer array round-trips (settings storage format)")
    func serverArrayRoundTrip() throws {
        let servers = [
            AgentServer(id: UUID(), name: "Local OC", type: .openclaw, url: "ws://127.0.0.1:18789", enabled: true),
            AgentServer(id: UUID(), name: "Hermes", type: .hermes, url: "http://127.0.0.1:8642", enabled: true),
        ]
        let data = try JSONEncoder().encode(servers)
        let decoded = try JSONDecoder().decode([AgentServer].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].type == .openclaw)
        #expect(decoded[1].type == .hermes)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift test --filter "AgentClientTests|AgentServerTests" 2>&1 | tail -20`
Expected: Compilation errors — types don't exist yet.

- [ ] **Step 3: Create AgentClient.swift**

```swift
// Sources/VoxOpsCore/Agent/AgentClient.swift
import Foundation

public struct ChatMessage: Codable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant, system }
    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public enum ServerType: String, Codable, Sendable {
    case openclaw
    case hermes
}

public enum AgentEvent: Sendable, Equatable {
    case textChunk(String)
    case error(String)
}

public protocol AgentClient: Sendable {
    var serverId: UUID { get }
    var serverType: ServerType { get }

    func connect() async throws
    func disconnect() async
    func listAgents() async throws -> [AgentProfile]
    func send(messages: [ChatMessage], agentId: String) -> AsyncThrowingStream<AgentEvent, Error>
    func healthCheck() async -> Bool
}
```

- [ ] **Step 4: Create AgentServer.swift**

```swift
// Sources/VoxOpsCore/Agent/AgentServer.swift
import Foundation

public struct AgentServer: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var type: ServerType
    public var url: String
    public var enabled: Bool

    public init(id: UUID = UUID(), name: String, type: ServerType, url: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.type = type
        self.url = url
        self.enabled = enabled
    }
}
```

- [ ] **Step 5: Create AgentProfile.swift**

```swift
// Sources/VoxOpsCore/Agent/AgentProfile.swift
import Foundation

public struct AgentProfile: Codable, Identifiable, Sendable, Equatable {
    /// Composite ID unique across servers: "serverId:agentId"
    public var id: String { "\(serverId):\(agentId)" }
    public let agentId: String
    public let serverId: UUID
    public var name: String
    public var enabled: Bool

    public init(id: String, serverId: UUID, name: String, enabled: Bool = true) {
        self.agentId = id
        self.serverId = serverId
        self.name = name
        self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey {
        case agentId = "id"
        case serverId, name, enabled
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift test --filter "AgentClientTests|AgentServerTests" 2>&1 | tail -20`
Expected: All 6 tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/VoxOpsCore/Agent/ Tests/VoxOpsCoreTests/AgentClientTests.swift Tests/VoxOpsCoreTests/AgentServerTests.swift
git commit -m "feat: add AgentClient protocol, ChatMessage, AgentServer, AgentProfile models"
```

---

## Task 3.5: KeychainStore — Auth Token Storage

**Files:**
- Create: `Sources/VoxOpsCore/Storage/KeychainStore.swift`
- Create: `Tests/VoxOpsCoreTests/KeychainStoreTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/VoxOpsCoreTests/KeychainStoreTests.swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("KeychainStore")
struct KeychainStoreTests {
    @Test("save and retrieve token")
    func saveAndRetrieve() throws {
        let store = KeychainStore()
        let key = "voxops.test.\(UUID().uuidString)"
        defer { store.delete(key: key) }
        try store.save(key: key, value: "test-token-123")
        let retrieved = store.retrieve(key: key)
        #expect(retrieved == "test-token-123")
    }

    @Test("retrieve returns nil for missing key")
    func retrieveMissing() {
        let store = KeychainStore()
        let result = store.retrieve(key: "voxops.nonexistent.\(UUID().uuidString)")
        #expect(result == nil)
    }

    @Test("delete removes stored token")
    func deleteToken() throws {
        let store = KeychainStore()
        let key = "voxops.test.\(UUID().uuidString)"
        try store.save(key: key, value: "to-delete")
        store.delete(key: key)
        #expect(store.retrieve(key: key) == nil)
    }

    @Test("save overwrites existing value")
    func overwrite() throws {
        let store = KeychainStore()
        let key = "voxops.test.\(UUID().uuidString)"
        defer { store.delete(key: key) }
        try store.save(key: key, value: "original")
        try store.save(key: key, value: "updated")
        #expect(store.retrieve(key: key) == "updated")
    }

    @Test("agentTokenKey formats correctly")
    func agentTokenKey() {
        let id = UUID()
        #expect(KeychainStore.agentTokenKey(serverId: id) == "voxops.agent.\(id)")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift test --filter KeychainStoreTests 2>&1 | tail -20`
Expected: Compilation errors.

- [ ] **Step 3: Implement KeychainStore**

```swift
// Sources/VoxOpsCore/Storage/KeychainStore.swift
import Foundation
import Security

public final class KeychainStore: Sendable {
    public init() {}

    public static func agentTokenKey(serverId: UUID) -> String {
        "voxops.agent.\(serverId)"
    }

    public func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        // Delete first to handle update case
        delete(key: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.voxops.agent-tokens",
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    public func retrieve(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.voxops.agent-tokens",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.voxops.agent-tokens",
            kSecAttrAccount as String: key,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}

public enum KeychainError: Error {
    case saveFailed(OSStatus)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift test --filter KeychainStoreTests 2>&1 | tail -20`
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoxOpsCore/Storage/KeychainStore.swift Tests/VoxOpsCoreTests/KeychainStoreTests.swift
git commit -m "feat: KeychainStore for secure agent auth token storage"
```

---

## Task 4: OpenClawClient — WebSocket Implementation

**Files:**
- Create: `Sources/VoxOpsCore/Agent/OpenClawClient.swift`
- Create: `Tests/VoxOpsCoreTests/OpenClawClientTests.swift`

- [ ] **Step 1: Write failing tests for OpenClaw frame parsing**

```swift
// Tests/VoxOpsCoreTests/OpenClawClientTests.swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("OpenClawClient")
struct OpenClawClientTests {
    @Test("builds connect frame with token")
    func connectFrame() throws {
        let frame = OpenClawFrames.connect(id: "test-id", token: "my-token")
        let data = try JSONSerialization.jsonObject(with: frame) as! [String: Any]
        #expect(data["type"] as? String == "req")
        #expect(data["method"] as? String == "connect")
        let params = data["params"] as! [String: Any]
        #expect(params["token"] as? String == "my-token")
    }

    @Test("builds agents.list frame")
    func agentsListFrame() throws {
        let frame = OpenClawFrames.agentsList(id: "test-id")
        let data = try JSONSerialization.jsonObject(with: frame) as! [String: Any]
        #expect(data["method"] as? String == "agents.list")
    }

    @Test("builds agent message frame")
    func agentFrame() throws {
        let frame = OpenClawFrames.agent(id: "test-id", message: "hello", agentId: "darth", idempotencyKey: "key-1")
        let data = try JSONSerialization.jsonObject(with: frame) as! [String: Any]
        #expect(data["method"] as? String == "agent")
        let params = data["params"] as! [String: Any]
        #expect(params["message"] as? String == "hello")
        #expect(params["agentId"] as? String == "darth")
        #expect(params["idempotencyKey"] as? String == "key-1")
    }

    @Test("parses agent text event")
    func parseAgentEvent() throws {
        let json = """
        {"type":"event","event":"agent","payload":{"runId":"xyz","type":"text","text":"Hello world","done":false}}
        """
        let (runId, event) = try OpenClawFrames.parseEvent(from: json.data(using: .utf8)!)
        #expect(runId == "xyz")
        if case .textChunk(let text) = event {
            #expect(text == "Hello world")
        } else {
            Issue.record("Expected textChunk event")
        }
    }

    @Test("parses agent done event with runId")
    func parseDoneEvent() throws {
        let json = """
        {"type":"event","event":"agent","payload":{"runId":"xyz","type":"text","text":"","done":true}}
        """
        let (runId, event) = try OpenClawFrames.parseEvent(from: json.data(using: .utf8)!)
        #expect(runId == "xyz")
        #expect(event == nil)
    }

    @Test("parses response frame for connect")
    func parseConnectResponse() throws {
        let json = """
        {"type":"res","id":"c1","ok":true,"payload":{"ok":true,"connect":{"role":"operator","scopes":["operator.read","operator.write"]}}}
        """
        let response = try OpenClawFrames.parseResponse(from: json.data(using: .utf8)!)
        #expect(response.ok == true)
        #expect(response.id == "c1")
    }

    @Test("parses error response frame")
    func parseErrorResponse() throws {
        let json = """
        {"type":"res","id":"e1","ok":false,"error":{"code":"AUTH_FAILED","message":"Invalid token"}}
        """
        let response = try OpenClawFrames.parseResponse(from: json.data(using: .utf8)!)
        #expect(response.ok == false)
        #expect(response.errorMessage == "Invalid token")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift test --filter OpenClawClientTests 2>&1 | tail -20`
Expected: Compilation errors — `OpenClawFrames` doesn't exist.

- [ ] **Step 3: Implement OpenClawClient**

```swift
// Sources/VoxOpsCore/Agent/OpenClawClient.swift
import Foundation

// MARK: - Frame building & parsing

public enum OpenClawFrames {
    public static func connect(id: String, token: String?) -> Data {
        var params: [String: Any] = [:]
        if let token { params["token"] = token }
        return buildRequest(id: id, method: "connect", params: params)
    }

    public static func agentsList(id: String) -> Data {
        buildRequest(id: id, method: "agents.list", params: [:])
    }

    public static func agent(id: String, message: String, agentId: String, idempotencyKey: String) -> Data {
        buildRequest(id: id, method: "agent", params: [
            "message": message,
            "agentId": agentId,
            "idempotencyKey": idempotencyKey,
        ])
    }

    /// Returns (runId, event) — event is nil for "done" signals
    public static func parseEvent(from data: Data) throws -> (runId: String?, event: AgentEvent?) {
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        guard let payload = json["payload"] as? [String: Any] else {
            throw OpenClawError.invalidFrame("Missing payload")
        }
        let runId = payload["runId"] as? String
        if let done = payload["done"] as? Bool, done { return (runId, nil) }
        if let text = payload["text"] as? String {
            return (runId, .textChunk(text))
        }
        return (runId, nil)
    }

    public static func parseResponse(from data: Data) throws -> OpenClawResponse {
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let id = json["id"] as? String ?? ""
        let ok = json["ok"] as? Bool ?? false
        var errorMessage: String?
        if let error = json["error"] as? [String: Any] {
            errorMessage = error["message"] as? String
        }
        return OpenClawResponse(id: id, ok: ok, payload: json["payload"], errorMessage: errorMessage)
    }

    public static func parseAgentsList(from payload: Any?) throws -> [AgentListEntry] {
        guard let dict = payload as? [String: Any],
              let entries = dict["entries"] as? [[String: Any]] else {
            return []
        }
        return entries.compactMap { entry in
            guard let id = entry["id"] as? String,
                  let name = entry["name"] as? String else { return nil }
            return AgentListEntry(id: id, name: name)
        }
    }

    private static func buildRequest(id: String, method: String, params: [String: Any]) -> Data {
        let frame: [String: Any] = ["type": "req", "id": id, "method": method, "params": params]
        return try! JSONSerialization.data(withJSONObject: frame)
    }
}

public struct OpenClawResponse {
    public let id: String
    public let ok: Bool
    public let payload: Any?
    public let errorMessage: String?
}

public struct AgentListEntry {
    public let id: String
    public let name: String
}

public enum OpenClawError: Error {
    case invalidFrame(String)
    case connectionFailed(String)
    case authFailed(String)
    case notConnected
}

// MARK: - WebSocket Client

public final class OpenClawClient: AgentClient, @unchecked Sendable {
    public let serverId: UUID
    public let serverType: ServerType = .openclaw

    private let url: URL
    private let token: String?
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pendingResponses: [String: CheckedContinuation<OpenClawResponse, Error>] = [:]
    private var eventContinuations: [String: AsyncThrowingStream<AgentEvent, Error>.Continuation] = [:]
    private var runIdToRequestId: [String: String] = [:]  // maps runId → requestId for event routing
    private let lock = NSLock()
    private var isConnected = false
    private var reconnectTask: Task<Void, Never>?
    private static let maxRetries = 5

    public init(serverId: UUID, url: URL, token: String?) {
        self.serverId = serverId
        self.url = url
        self.token = token
    }

    public func connect() async throws {
        let session = URLSession(configuration: .default)
        self.session = session
        let ws = session.webSocketTask(with: url)
        self.webSocket = ws
        ws.resume()
        startReceiving()

        let connectId = UUID().uuidString
        let response = try await sendAndWait(
            id: connectId,
            data: OpenClawFrames.connect(id: connectId, token: token)
        )
        guard response.ok else {
            throw OpenClawError.authFailed(response.errorMessage ?? "Authentication failed")
        }
        lock.lock()
        isConnected = true
        lock.unlock()
    }

    public func disconnect() async {
        lock.lock()
        isConnected = false
        reconnectTask?.cancel()
        reconnectTask = nil
        lock.unlock()
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
    }

    public func listAgents() async throws -> [AgentProfile] {
        let id = UUID().uuidString
        let response = try await sendAndWait(
            id: id,
            data: OpenClawFrames.agentsList(id: id)
        )
        guard response.ok else {
            throw OpenClawError.connectionFailed(response.errorMessage ?? "Failed to list agents")
        }
        let entries = try OpenClawFrames.parseAgentsList(from: response.payload)
        return entries.map { AgentProfile(id: $0.id, serverId: serverId, name: $0.name) }  // AgentProfile.init(id:) maps to agentId
    }

    public func send(messages: [ChatMessage], agentId: String) -> AsyncThrowingStream<AgentEvent, Error> {
        let message = messages.last(where: { $0.role == .user })?.content ?? ""
        let requestId = UUID().uuidString
        let idempotencyKey = UUID().uuidString
        let frameData = OpenClawFrames.agent(
            id: requestId, message: message, agentId: agentId, idempotencyKey: idempotencyKey
        )

        return AsyncThrowingStream { continuation in
            lock.lock()
            eventContinuations[requestId] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.eventContinuations.removeValue(forKey: requestId)
                self?.lock.unlock()
            }

            guard let ws = webSocket else {
                continuation.finish(throwing: OpenClawError.notConnected)
                return
            }
            ws.send(.data(frameData)) { error in
                if let error {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func healthCheck() async -> Bool {
        lock.lock()
        let connected = isConnected
        lock.unlock()
        return connected
    }

    // MARK: - Private

    private func sendAndWait(id: String, data: Data) async throws -> OpenClawResponse {
        guard let ws = webSocket else { throw OpenClawError.notConnected }
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pendingResponses[id] = continuation
            lock.unlock()
            ws.send(.data(data)) { [weak self] error in
                if let error {
                    self?.lock.lock()
                    let cont = self?.pendingResponses.removeValue(forKey: id)
                    self?.lock.unlock()
                    cont?.resume(throwing: error)
                }
            }
        }
    }

    private func startReceiving() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.startReceiving()
            case .failure(let error):
                self.handleDisconnect(error: error)
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = s.data(using: .utf8) ?? Data()
        @unknown default: return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "res":
            guard let id = json["id"] as? String,
                  let response = try? OpenClawFrames.parseResponse(from: data) else { return }
            lock.lock()
            // Map runId → requestId for event routing
            if let payload = response.payload as? [String: Any],
               let runId = payload["runId"] as? String {
                runIdToRequestId[runId] = id
            }
            let continuation = pendingResponses.removeValue(forKey: id)
            lock.unlock()
            continuation?.resume(returning: response)

        case "event":
            guard let parsed = try? OpenClawFrames.parseEvent(from: data) else { return }
            let (runId, event) = parsed
            lock.lock()
            let requestId = runId.flatMap { runIdToRequestId[$0] }
            if let event {
                // Route to specific stream by requestId, or broadcast if no mapping
                if let requestId, let cont = eventContinuations[requestId] {
                    lock.unlock()
                    cont.yield(event)
                } else {
                    let continuations = Array(eventContinuations.values)
                    lock.unlock()
                    for cont in continuations { cont.yield(event) }
                }
            } else {
                // done — finish the specific stream
                if let requestId {
                    let cont = eventContinuations.removeValue(forKey: requestId)
                    runIdToRequestId.removeValue(forKey: runId!)
                    lock.unlock()
                    cont?.finish()
                } else {
                    let continuations = eventContinuations
                    eventContinuations.removeAll()
                    runIdToRequestId.removeAll()
                    lock.unlock()
                    for (_, cont) in continuations { cont.finish() }
                }
            }
        default: break
        }
    }

    private func handleDisconnect(error: Error) {
        lock.lock()
        isConnected = false
        let responseContinuations = pendingResponses
        pendingResponses.removeAll()
        let streamContinuations = eventContinuations
        eventContinuations.removeAll()
        lock.unlock()

        for (_, cont) in responseContinuations {
            cont.resume(throwing: error)
        }
        for (_, cont) in streamContinuations {
            cont.finish(throwing: error)
        }

        // Auto-reconnect with exponential backoff
        reconnectTask = Task { [weak self] in
            for attempt in 0..<Self.maxRetries {
                let delay = min(pow(2.0, Double(attempt)), 8.0)
                let jitter = Double.random(in: 0...0.5)
                try? await Task.sleep(nanoseconds: UInt64((delay + jitter) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                do {
                    try await self?.connect()
                    return // success
                } catch {
                    continue
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift test --filter OpenClawClientTests 2>&1 | tail -20`
Expected: All 7 tests pass (frame building/parsing tests — no actual WebSocket connection).

- [ ] **Step 5: Commit**

```bash
git add Sources/VoxOpsCore/Agent/OpenClawClient.swift Tests/VoxOpsCoreTests/OpenClawClientTests.swift
git commit -m "feat: OpenClawClient WebSocket implementation with frame protocol"
```

---

## Task 5: HermesClient — HTTP/SSE Implementation

**Files:**
- Create: `Sources/VoxOpsCore/Agent/HermesClient.swift`
- Create: `Tests/VoxOpsCoreTests/HermesClientTests.swift`

- [ ] **Step 1: Write failing tests for Hermes SSE parsing and request building**

```swift
// Tests/VoxOpsCoreTests/HermesClientTests.swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("HermesClient")
struct HermesClientTests {
    @Test("builds chat completions request body")
    func requestBody() throws {
        let messages = [
            ChatMessage(role: .system, content: "You are helpful"),
            ChatMessage(role: .user, content: "Hello"),
        ]
        let body = HermesRequestBuilder.chatCompletions(messages: messages, stream: true)
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        #expect(json["model"] as? String == "hermes-agent")
        #expect(json["stream"] as? Bool == true)
        let msgs = json["messages"] as! [[String: String]]
        #expect(msgs.count == 2)
        #expect(msgs[0]["role"] == "system")
        #expect(msgs[1]["content"] == "Hello")
    }

    @Test("parses SSE data line into text chunk")
    func parseSSEChunk() throws {
        let line = #"data: {"choices":[{"delta":{"content":"Hello"},"index":0}]}"#
        let event = HermesSSEParser.parseLine(line)
        if case .textChunk(let text) = event {
            #expect(text == "Hello")
        } else {
            Issue.record("Expected textChunk, got \(String(describing: event))")
        }
    }

    @Test("parses SSE DONE sentinel as nil")
    func parseDoneSentinel() {
        let event = HermesSSEParser.parseLine("data: [DONE]")
        #expect(event == nil)
    }

    @Test("ignores non-data SSE lines")
    func ignoresNonData() {
        #expect(HermesSSEParser.parseLine("event: ping") == nil)
        #expect(HermesSSEParser.parseLine(": keep-alive") == nil)
        #expect(HermesSSEParser.parseLine("") == nil)
    }

    @Test("parses SSE chunk with empty content")
    func emptyContent() {
        let line = #"data: {"choices":[{"delta":{"content":""},"index":0}]}"#
        let event = HermesSSEParser.parseLine(line)
        // Empty content should still yield a chunk (some models send empty deltas)
        if case .textChunk(let text) = event {
            #expect(text == "")
        } else {
            Issue.record("Expected textChunk with empty string")
        }
    }

    @Test("parses SSE chunk with no content key (role-only delta)")
    func roleOnlyDelta() {
        let line = #"data: {"choices":[{"delta":{"role":"assistant"},"index":0}]}"#
        let event = HermesSSEParser.parseLine(line)
        #expect(event == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift test --filter HermesClientTests 2>&1 | tail -20`
Expected: Compilation errors — `HermesRequestBuilder` and `HermesSSEParser` don't exist.

- [ ] **Step 3: Implement HermesClient**

```swift
// Sources/VoxOpsCore/Agent/HermesClient.swift
import Foundation

// MARK: - Request building

public enum HermesRequestBuilder {
    public static func chatCompletions(messages: [ChatMessage], stream: Bool) -> Data {
        let msgs = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        let body: [String: Any] = [
            "model": "hermes-agent",
            "messages": msgs,
            "stream": stream,
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }
}

// MARK: - SSE parsing

public enum HermesSSEParser {
    /// Parses a single SSE line. Returns nil for non-data lines, DONE sentinel, or deltas without content.
    public static func parseLine(_ line: String) -> AgentEvent? {
        guard line.hasPrefix("data: ") else { return nil }
        let payload = String(line.dropFirst(6))
        if payload == "[DONE]" { return nil }

        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any] else {
            return nil
        }

        // Only yield if content key is present (role-only deltas return nil)
        guard delta.keys.contains("content") else { return nil }
        let content = delta["content"] as? String ?? ""
        return .textChunk(content)
    }
}

// MARK: - Hermes errors

public enum HermesError: Error {
    case invalidURL
    case httpError(statusCode: Int, body: String)
    case noResponse
}

// MARK: - Client

public final class HermesClient: AgentClient, @unchecked Sendable {
    public let serverId: UUID
    public let serverType: ServerType = .hermes

    private let baseURL: URL
    private let token: String?
    private let agentName: String
    private let session: URLSession

    public init(serverId: UUID, baseURL: URL, token: String?, agentName: String = "Hermes") {
        self.serverId = serverId
        self.baseURL = baseURL
        self.token = token
        self.agentName = agentName
        self.session = URLSession(configuration: .default)
    }

    public func connect() async throws {
        // HTTP is stateless — just verify the endpoint is reachable
        let ok = await healthCheck()
        if !ok { throw HermesError.noResponse }
    }

    public func disconnect() async {
        // No persistent connection to close
    }

    public func listAgents() async throws -> [AgentProfile] {
        // Hermes is one agent per endpoint
        [AgentProfile(id: "hermes", serverId: serverId, name: agentName)]
    }

    public func send(messages: [ChatMessage], agentId: String) -> AsyncThrowingStream<AgentEvent, Error> {
        let url = baseURL.appendingPathComponent("v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = HermesRequestBuilder.chatCompletions(messages: messages, stream: true)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                        continuation.finish(throwing: HermesError.httpError(
                            statusCode: httpResponse.statusCode, body: "HTTP \(httpResponse.statusCode)"))
                        return
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if let event = HermesSSEParser.parseLine(line) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func healthCheck() async -> Bool {
        let url = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift test --filter HermesClientTests 2>&1 | tail -20`
Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoxOpsCore/Agent/HermesClient.swift Tests/VoxOpsCoreTests/HermesClientTests.swift
git commit -m "feat: HermesClient HTTP/SSE implementation with request builder and SSE parser"
```

---

## Task 6: AgentClientManager

**Files:**
- Create: `Sources/VoxOpsCore/Agent/AgentClientManager.swift`
- Create: `Tests/VoxOpsCoreTests/AgentClientManagerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/VoxOpsCoreTests/AgentClientManagerTests.swift
import Testing
import Foundation
@testable import VoxOpsCore

// Mock client for testing
final class MockAgentClient: AgentClient, @unchecked Sendable {
    let serverId: UUID
    let serverType: ServerType
    var connectCalled = false
    var disconnectCalled = false
    var mockAgents: [AgentProfile] = []
    var shouldFailConnect = false

    init(serverId: UUID, serverType: ServerType, mockAgents: [AgentProfile] = []) {
        self.serverId = serverId
        self.serverType = serverType
        self.mockAgents = mockAgents
    }

    func connect() async throws {
        if shouldFailConnect { throw OpenClawError.connectionFailed("mock fail") }
        connectCalled = true
    }
    func disconnect() async { disconnectCalled = true }
    func listAgents() async throws -> [AgentProfile] { mockAgents }
    func send(messages: [ChatMessage], agentId: String) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func healthCheck() async -> Bool { connectCalled }
}

@Suite("AgentClientManager")
struct AgentClientManagerTests {
    @Test("registers and retrieves client by serverId")
    @MainActor func registerAndRetrieve() async {
        let manager = AgentClientManager()
        let id = UUID()
        let client = MockAgentClient(serverId: id, serverType: .openclaw)
        manager.register(client: client)
        let retrieved = manager.client(for: id)
        #expect(retrieved != nil)
        #expect(retrieved?.serverId == id)
    }

    @Test("allAgents aggregates from all clients")
    @MainActor func allAgents() async throws {
        let manager = AgentClientManager()
        let id1 = UUID()
        let id2 = UUID()
        let client1 = MockAgentClient(serverId: id1, serverType: .openclaw, mockAgents: [
            AgentProfile(id: "a1", serverId: id1, name: "Agent 1"),
            AgentProfile(id: "a2", serverId: id1, name: "Agent 2"),
        ])
        let client2 = MockAgentClient(serverId: id2, serverType: .hermes, mockAgents: [
            AgentProfile(id: "hermes", serverId: id2, name: "Hermes"),
        ])
        manager.register(client: client1)
        manager.register(client: client2)
        let agents = try await manager.allAgents()
        #expect(agents.count == 3)
    }

    @Test("removeClient disconnects and removes")
    @MainActor func removeClient() async {
        let manager = AgentClientManager()
        let id = UUID()
        let client = MockAgentClient(serverId: id, serverType: .openclaw)
        manager.register(client: client)
        await manager.removeClient(for: id)
        let retrieved = manager.client(for: id)
        #expect(retrieved == nil)
        #expect(client.disconnectCalled)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift test --filter AgentClientManagerTests 2>&1 | tail -20`
Expected: Compilation errors.

- [ ] **Step 3: Implement AgentClientManager**

```swift
// Sources/VoxOpsCore/Agent/AgentClientManager.swift
import Foundation

/// Manages all agent client connections. Runs on @MainActor to avoid
/// hop overhead with ChatViewModel and AppState (both @MainActor).
@MainActor
public final class AgentClientManager {
    private var clients: [UUID: any AgentClient] = [:]

    public init() {}

    public func register(client: any AgentClient) {
        clients[client.serverId] = client
    }

    public func client(for serverId: UUID) -> (any AgentClient)? {
        clients[serverId]
    }

    public func removeClient(for serverId: UUID) async {
        if let client = clients.removeValue(forKey: serverId) {
            await client.disconnect()
        }
    }

    public func allAgents() async throws -> [AgentProfile] {
        var all: [AgentProfile] = []
        for (_, client) in clients {
            let agents = try await client.listAgents()
            all.append(contentsOf: agents)
        }
        return all
    }

    public func allEnabledAgents() async throws -> [AgentProfile] {
        try await allAgents().filter(\.enabled)
    }

    public func connectAll() async {
        for (_, client) in clients {
            try? await client.connect()
        }
    }

    public func disconnectAll() async {
        for (_, client) in clients {
            await client.disconnect()
        }
        clients.removeAll()
    }

    public func clientForAgent(_ agentId: String, serverId: UUID) -> (any AgentClient)? {
        clients[serverId]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift test --filter AgentClientManagerTests 2>&1 | tail -20`
Expected: All 3 tests pass.

- [ ] **Step 5: Run all tests**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift test 2>&1 | tail -20`
Expected: All tests pass (some AppState compilation might fail — that's addressed in Task 8).

- [ ] **Step 6: Commit**

```bash
git add Sources/VoxOpsCore/Agent/AgentClientManager.swift Tests/VoxOpsCoreTests/AgentClientManagerTests.swift
git commit -m "feat: AgentClientManager actor for multi-server lifecycle"
```

---

## Task 7: Chat Window — NSPanel + SwiftUI Chat UI

**Files:**
- Create: `VoxOpsApp/Views/ChatWindow.swift`
- Create: `VoxOpsApp/Views/ChatView.swift`
- Create: `VoxOpsApp/Views/ChatViewModel.swift`

No unit tests for UI code — these are manually tested.

- [ ] **Step 1: Create ChatWindow NSPanel**

```swift
// VoxOpsApp/Views/ChatWindow.swift
import AppKit
import SwiftUI

final class ChatWindow: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        self.contentView = contentView
        self.title = "VoxOps Agent Chat"
        self.isFloatingPanel = true
        self.level = .floating
        // Becomes key when user clicks into text field, but does not activate the app
        self.becomesKeyOnlyIfNeeded = true
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces]
        self.isMovableByWindowBackground = false
        self.minSize = NSSize(width: 360, height: 400)
        self.center()
    }
}
```

- [ ] **Step 2: Create ChatViewModel**

```swift
// VoxOpsApp/Views/ChatViewModel.swift
import Foundation
import VoxOpsCore

struct ChatBubble: Identifiable {
    let id = UUID()
    let role: ChatMessage.Role
    var text: String
    let timestamp: Date

    init(role: ChatMessage.Role, text: String) {
        self.role = role
        self.text = text
        self.timestamp = Date()
    }
}

/// Counter that increments on every streaming chunk to trigger auto-scroll
@MainActor
final class ScrollTrigger: ObservableObject {
    @Published var value: Int = 0
    func bump() { value += 1 }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var bubbles: [ChatBubble] = []
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = false

    let agent: AgentProfile
    let scrollTrigger = ScrollTrigger()
    private let clientManager: AgentClientManager
    private var streamTask: Task<Void, Never>?

    init(agent: AgentProfile, clientManager: AgentClientManager) {
        self.agent = agent
        self.clientManager = clientManager
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        inputText = ""

        bubbles.append(ChatBubble(role: .user, text: text))

        // Build full message history for the client
        let messages = bubbles.map { ChatMessage(role: $0.role, content: $0.text) }

        // Add empty assistant bubble for streaming
        let assistantBubble = ChatBubble(role: .assistant, text: "")
        bubbles.append(assistantBubble)
        let bubbleIndex = bubbles.count - 1

        isStreaming = true
        streamTask = Task {
            defer { isStreaming = false }
            guard let client = await clientManager.client(for: agent.serverId) else {
                bubbles[bubbleIndex].text = "[Error: Server not connected]"
                return
            }
            let stream = client.send(messages: messages, agentId: agent.agentId)
            do {
                for try await event in stream {
                    switch event {
                    case .textChunk(let chunk):
                        bubbles[bubbleIndex].text += chunk
                        scrollTrigger.bump()
                    case .error(let message):
                        bubbles[bubbleIndex].text += "\n[Error: \(message)]"
                    }
                }
            } catch {
                if bubbles[bubbleIndex].text.isEmpty {
                    bubbles[bubbleIndex].text = "[Error: \(error.localizedDescription)]"
                }
            }
        }
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }
}
```

- [ ] **Step 3: Create ChatView**

```swift
// VoxOpsApp/Views/ChatView.swift
import SwiftUI
import VoxOpsCore

struct ChatView: View {
    let agents: [AgentProfile]
    let clientManager: AgentClientManager
    @State private var selectedAgentId: String?  // composite id: "serverId:agentId"
    @State private var viewModels: [String: ChatViewModel] = [:]  // keyed by agent.id (composite)

    var body: some View {
        VStack(spacing: 0) {
            if agents.isEmpty {
                emptyState
            } else {
                tabBar
                Divider()
                if let agentId = selectedAgentId, let vm = viewModels[agentId] {
                    chatContent(vm: vm)
                }
            }
        }
        .onAppear { setupViewModels() }
        .onChange(of: agents.map(\.id)) { _, _ in setupViewModels() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("No agents configured")
                .font(.headline).foregroundStyle(.secondary)
            Text("Add agent servers in Settings > Agents")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(agents) { agent in
                    Button {
                        selectedAgentId = agent.id
                    } label: {
                        Text(agent.name)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedAgentId == agent.id ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private func chatContent(vm: ChatViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(vm.bubbles) { bubble in
                            HStack {
                                if bubble.role == .user { Spacer() }
                                Text(bubble.text.isEmpty && vm.isStreaming ? "..." : bubble.text)
                                    .padding(8)
                                    .background(bubble.role == .user ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                    .cornerRadius(8)
                                    .textSelection(.enabled)
                                if bubble.role != .user { Spacer() }
                            }
                            .id(bubble.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: vm.bubbles.count) { _, _ in
                    if let last = vm.bubbles.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: vm.scrollTrigger.value) { _, _ in
                    if let last = vm.bubbles.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()
            inputBar(vm: vm)
        }
    }

    private func inputBar(vm: ChatViewModel) -> some View {
        HStack(spacing: 8) {
            TextField("Message...", text: Binding(
                get: { vm.inputText },
                set: { vm.inputText = $0 }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...5)
            .onSubmit { vm.sendMessage() }
            .padding(8)

            Button {
                if vm.isStreaming { vm.cancelStream() } else { vm.sendMessage() }
            } label: {
                Image(systemName: vm.isStreaming ? "stop.circle" : "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!vm.isStreaming && vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.trailing, 8)
        }
        .padding(.vertical, 4)
    }

    private func setupViewModels() {
        for agent in agents where viewModels[agent.id] == nil {
            viewModels[agent.id] = ChatViewModel(agent: agent, clientManager: clientManager)
        }
        if selectedAgentId == nil || !agents.contains(where: { $0.id == selectedAgentId }) {
            selectedAgentId = agents.first?.id
        }
    }
}
```

- [ ] **Step 4: Verify project compiles**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift build 2>&1 | tail -20`
Expected: May show warnings but should compile. If AppState errors occur, that's fixed in Task 8.

- [ ] **Step 5: Commit**

```bash
git add VoxOpsApp/Views/ChatWindow.swift VoxOpsApp/Views/ChatView.swift VoxOpsApp/Views/ChatViewModel.swift
git commit -m "feat: chat window UI with tabbed agent conversations and streaming"
```

---

## Task 8: Settings UI — Agents Tab + Server Form

**Files:**
- Create: `VoxOpsApp/Views/AgentSettingsView.swift`
- Create: `VoxOpsApp/Views/ServerFormView.swift`
- Modify: `VoxOpsApp/Views/SettingsView.swift`

- [ ] **Step 1: Create ServerFormView**

```swift
// VoxOpsApp/Views/ServerFormView.swift
import SwiftUI
import VoxOpsCore

struct ServerFormView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (AgentServer) -> Void

    @State private var name: String
    @State private var serverType: ServerType
    @State private var url: String
    @State private var token: String
    @State private var testResult: String?
    @State private var isTesting: Bool = false
    private let existingId: UUID?

    init(server: AgentServer? = nil, onSave: @escaping (AgentServer) -> Void) {
        self.onSave = onSave
        self.existingId = server?.id
        _name = State(initialValue: server?.name ?? "")
        _serverType = State(initialValue: server?.type ?? .openclaw)
        _url = State(initialValue: server?.url ?? "")
        _token = State(initialValue: "")
    }

    var body: some View {
        Form {
            TextField("Name", text: $name)
            Picker("Type", selection: $serverType) {
                Text("OpenClaw").tag(ServerType.openclaw)
                Text("Hermes").tag(ServerType.hermes)
            }
            .onChange(of: serverType) { _, newType in
                if url.isEmpty {
                    url = newType == .openclaw ? "ws://127.0.0.1:18789" : "http://127.0.0.1:8642"
                }
            }
            TextField("URL", text: $url)
                .textFieldStyle(.roundedBorder)
            SecureField("Token", text: $token)
                .textFieldStyle(.roundedBorder)

            if let result = testResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(result.contains("Success") ? .green : .red)
            }

            HStack {
                Button("Test Connection") { testConnection() }
                    .disabled(isTesting || url.isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .disabled(name.isEmpty || url.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func save() {
        let server = AgentServer(
            id: existingId ?? UUID(),
            name: name,
            type: serverType,
            url: url,
            enabled: true
        )
        // Persist token to Keychain if provided
        if !token.isEmpty {
            let keychain = KeychainStore()
            try? keychain.save(key: KeychainStore.agentTokenKey(serverId: server.id), value: token)
        }
        onSave(server)
        dismiss()
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            defer { isTesting = false }
            guard let testURL = URL(string: url) else {
                testResult = "Invalid URL"
                return
            }
            if serverType == .hermes {
                let client = HermesClient(serverId: UUID(), baseURL: testURL, token: token.isEmpty ? nil : token)
                let ok = await client.healthCheck()
                testResult = ok ? "Success — connected" : "Failed — server unreachable"
            } else {
                do {
                    let client = OpenClawClient(serverId: UUID(), url: testURL, token: token.isEmpty ? nil : token)
                    try await client.connect()
                    await client.disconnect()
                    testResult = "Success — connected"
                } catch {
                    testResult = "Failed — \(error.localizedDescription)"
                }
            }
        }
    }
}
```

- [ ] **Step 2: Create AgentSettingsView**

```swift
// VoxOpsApp/Views/AgentSettingsView.swift
import SwiftUI
import VoxOpsCore

struct AgentSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var showingAddServer = false
    @State private var editingServer: AgentServer?

    var body: some View {
        Form {
            Section("Servers") {
                if appState.agentServers.isEmpty {
                    Text("No servers configured").foregroundStyle(.secondary)
                } else {
                    ForEach(appState.agentServers) { server in
                        HStack {
                            Circle()
                                .fill(server.enabled ? .green : .gray)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading) {
                                Text(server.name).font(.body)
                                Text("\(server.type.rawValue) — \(server.url)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { editingServer = server } label: {
                                Image(systemName: "pencil")
                            }.buttonStyle(.plain)
                            Button { appState.removeServer(server.id) } label: {
                                Image(systemName: "xmark")
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Button("Add Server...") { showingAddServer = true }
            }

            Section("Chat Hotkey") {
                Text("Current: \(appState.chatTrigger?.displayString ?? "Not set")")
                    .font(.headline)
                ChatHotkeyRecorder(appState: appState)
            }
        }
        .padding()
        .sheet(isPresented: $showingAddServer) {
            ServerFormView { server in appState.addServer(server) }
        }
        .sheet(item: $editingServer) { server in
            ServerFormView(server: server) { updated in appState.updateServer(updated) }
        }
    }
}

private struct ChatHotkeyRecorder: View {
    @ObservedObject var appState: AppState
    @State private var isRecording = false
    @State private var recordingError: String?

    var body: some View {
        Button(isRecording ? "Press your shortcut..." : "Record Chat Hotkey...") {
            isRecording = true
            recordingError = nil
        }
        .disabled(isRecording)
        .onKeyDown(isActive: $isRecording) { keyCode, modifiers in
            if keyCode == 0x35 { // Escape
                isRecording = false
                recordingError = nil
                return true
            }
            let modifierKeys = modifiers.toModifierKeys()
            guard !modifierKeys.isEmpty else { return false }
            let trigger = HotkeyTrigger(keyCode: keyCode, modifiers: modifierKeys)
            if let error = trigger.validate() {
                recordingError = error
                return true
            }
            if trigger == appState.currentTrigger {
                recordingError = "Cannot be the same as voice hotkey"
                return true
            }
            isRecording = false
            recordingError = nil
            appState.saveChatTrigger(trigger)
            return true
        }
        if let error = recordingError {
            Text(error).foregroundStyle(.red).font(.caption)
        }
    }
}
```

- [ ] **Step 3: Update SettingsView — remove mouse picker, add Agents tab**

In `VoxOpsApp/Views/SettingsView.swift`, make these changes:

1. Remove `@State private var selectedMouseButton = 0`
2. Remove the mouse button `onAppear` logic
3. Remove the entire mouse button `Picker` and its `.onChange`
4. Remove `selectedMouseButton = 0` from the reset button action
5. Add the Agents tab to the `TabView`
6. Update the keyboard recorder to use `HotkeyTrigger(keyCode:modifiers:)` init instead of `.keyboard(keyCode:modifiers:)`

The updated file:

```swift
// VoxOpsApp/Views/SettingsView.swift
import SwiftUI
import VoxOpsCore

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selectedBackend = "whisper.cpp"
    @State private var isRecording = false
    @State private var recordingError: String?

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            audioTab.tabItem { Label("Audio", systemImage: "mic") }
            AgentSettingsView(appState: appState).tabItem { Label("Agents", systemImage: "bubble.left.and.bubble.right") }
        }
        .frame(width: 450, height: 400)
        .onAppear {
            selectedBackend = appState.selectedBackend
        }
    }

    private var generalTab: some View {
        Form {
            Section("Push-to-Talk Trigger") {
                Text("Current: \(appState.currentTrigger.displayString)")
                    .font(.headline)

                Button(isRecording ? "Press your shortcut..." : "Record Keyboard Shortcut...") {
                    isRecording = true
                    recordingError = nil
                }
                .disabled(isRecording)
                .onKeyDown(isActive: $isRecording) { keyCode, modifiers in
                    if keyCode == 0x35 {
                        isRecording = false
                        recordingError = nil
                        return true
                    }
                    let modifierKeys = modifiers.toModifierKeys()
                    guard !modifierKeys.isEmpty else { return false }
                    let trigger = HotkeyTrigger(keyCode: keyCode, modifiers: modifierKeys)
                    if let error = trigger.validate() {
                        recordingError = error
                        return true
                    }
                    if trigger == appState.chatTrigger {
                        recordingError = "Cannot be the same as chat hotkey"
                        return true
                    }
                    isRecording = false
                    recordingError = nil
                    appState.saveTrigger(trigger)
                    return true
                }

                if let error = recordingError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }

                Button("Reset to Default") {
                    appState.saveTrigger(.default)
                }
                .font(.caption)
            }

            Section("After Injection") {
                Toggle("Press Enter after pasting text", isOn: Binding(
                    get: { appState.autoEnterEnabled },
                    set: { appState.saveAutoEnter($0) }
                ))
                Text("Sends Return keystroke after text is injected.")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Section("STT Backend") {
                Picker("Backend", selection: $selectedBackend) {
                    Text("whisper.cpp").tag("whisper.cpp")
                    Text("MLX Whisper").tag("mlx-whisper")
                }
                .onChange(of: selectedBackend) { _, newValue in appState.selectedBackend = newValue }
            }
        }.padding()
    }

    private var audioTab: some View {
        Form {
            Section("Microphone") {
                Text("Using system default microphone").foregroundStyle(.secondary)
                Text("Microphone selection coming in a future update.").font(.caption).foregroundStyle(.tertiary)
            }
        }.padding()
    }
}

// MARK: - Key event capture for the recorder

struct KeyDownHandler: ViewModifier {
    @Binding var isActive: Bool
    let handler: (UInt16, NSEvent.ModifierFlags) -> Bool
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive) { _, active in
                if active {
                    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                        if handler(UInt16(event.keyCode), event.modifierFlags) {
                            return nil
                        }
                        return event
                    }
                } else {
                    if let monitor { NSEvent.removeMonitor(monitor) }
                    monitor = nil
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

extension View {
    func onKeyDown(isActive: Binding<Bool>, handler: @escaping (UInt16, NSEvent.ModifierFlags) -> Bool) -> some View {
        modifier(KeyDownHandler(isActive: isActive, handler: handler))
    }
}

extension NSEvent.ModifierFlags {
    func toModifierKeys() -> [ModifierKey] {
        var keys: [ModifierKey] = []
        if contains(.command) { keys.append(.command) }
        if contains(.option) { keys.append(.option) }
        if contains(.control) { keys.append(.control) }
        if contains(.shift) { keys.append(.shift) }
        return keys
    }
}
```

- [ ] **Step 4: Verify project compiles**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift build 2>&1 | tail -20`
Expected: Will fail because SettingsView references `appState.chatTrigger` and `appState.agentServers` which don't exist until Task 9. **This is expected.** Proceed to Task 9 which adds these properties. After Task 9, come back and verify everything compiles.

- [ ] **Step 5: Commit**

```bash
git add VoxOpsApp/Views/AgentSettingsView.swift VoxOpsApp/Views/ServerFormView.swift VoxOpsApp/Views/SettingsView.swift
git commit -m "feat: Agent settings UI with server management and chat hotkey recorder"
```

---

## Task 9: Wire Everything Together in AppState

**Files:**
- Modify: `VoxOpsApp/AppState.swift`

- [ ] **Step 1: Update AppState to support agent integration**

Add to `AppState`:
- `agentServers` published property
- `chatTrigger` published property
- `agentClientManager` property
- Chat window management
- Server CRUD methods
- Chat hotkey wiring
- Hotkey collision validation

```swift
// VoxOpsApp/AppState.swift
import Foundation
import SwiftUI
import VoxOpsCore

@MainActor
final class AppState: ObservableObject {
    @Published var voxState: VoxState = .idle
    @Published var lastTranscript: String = ""
    @Published var selectedBackend: String = "whisper.cpp"
    @Published var isSettingsOpen = false
    private var settingsWindow: NSWindow?
    @Published var currentTrigger: HotkeyTrigger = .default
    @Published var autoEnterEnabled: Bool = false
    @Published var agentServers: [AgentServer] = []
    @Published var chatTrigger: HotkeyTrigger?

    private var database: Database?
    private var settingsStore: SettingsStore?
    private var audioManager: AudioManager?
    private var hotkeyManager: HotkeyManager?
    private var textInjector: TextInjector?
    private var rawFormatter: RawFormatter?
    private var activeBackend: (any STTBackend)?
    let agentClientManager = AgentClientManager()
    private var chatWindow: NSPanel?
    private var chatAgents: [AgentProfile] = []

    init() {
        DispatchQueue.main.async { [weak self] in self?.setup() }
    }

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
            loadSettings()
            setupHotkey()
            Task { await setupAgentClients() }
        } catch {
            voxState = .error("Setup failed: \(error.localizedDescription)")
        }
    }

    private func loadSettings() {
        guard let store = settingsStore else { return }
        if let json = try? store.getString("hotkey_trigger"),
           let data = json.data(using: .utf8),
           let trigger = try? JSONDecoder().decode(HotkeyTrigger.self, from: data) {
            currentTrigger = trigger
        }
        if let json = try? store.getString("hotkey_chat_trigger"),
           let data = json.data(using: .utf8),
           let trigger = try? JSONDecoder().decode(HotkeyTrigger.self, from: data) {
            chatTrigger = trigger
        }
        if let value = try? store.getString("auto_enter") {
            autoEnterEnabled = value == "true"
        }
        if let json = try? store.getString("agent_servers"),
           let data = json.data(using: .utf8),
           let servers = try? JSONDecoder().decode([AgentServer].self, from: data) {
            agentServers = servers
        }
    }

    func saveTrigger(_ trigger: HotkeyTrigger) {
        guard let store = settingsStore else { return }
        if let data = try? JSONEncoder().encode(trigger),
           let json = String(data: data, encoding: .utf8) {
            try? store.setString("hotkey_trigger", value: json)
        }
        currentTrigger = trigger
        reloadHotkey()
    }

    func saveChatTrigger(_ trigger: HotkeyTrigger) {
        guard let store = settingsStore else { return }
        if let data = try? JSONEncoder().encode(trigger),
           let json = String(data: data, encoding: .utf8) {
            try? store.setString("hotkey_chat_trigger", value: json)
        }
        chatTrigger = trigger
        reloadHotkey()
    }

    func openSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let settingsView = SettingsView(appState: self)
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "VoxOps Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }

    func saveAutoEnter(_ enabled: Bool) {
        guard let store = settingsStore else { return }
        try? store.setString("auto_enter", value: enabled ? "true" : "false")
        autoEnterEnabled = enabled
    }

    // MARK: - Agent Server CRUD

    func addServer(_ server: AgentServer) {
        agentServers.append(server)
        saveServers()
        Task { await registerClient(for: server) }
    }

    func updateServer(_ server: AgentServer) {
        if let idx = agentServers.firstIndex(where: { $0.id == server.id }) {
            agentServers[idx] = server
            saveServers()
            Task {
                await agentClientManager.removeClient(for: server.id)
                await registerClient(for: server)
            }
        }
    }

    func removeServer(_ id: UUID) {
        agentServers.removeAll { $0.id == id }
        saveServers()
        Task { await agentClientManager.removeClient(for: id) }
    }

    private func saveServers() {
        guard let store = settingsStore else { return }
        if let data = try? JSONEncoder().encode(agentServers),
           let json = String(data: data, encoding: .utf8) {
            try? store.setString("agent_servers", value: json)
        }
    }

    // MARK: - Agent Client Setup

    private func setupAgentClients() async {
        for server in agentServers where server.enabled {
            await registerClient(for: server)
        }
    }

    private func registerClient(for server: AgentServer) async {
        guard let url = URL(string: server.url) else { return }
        let keychain = KeychainStore()
        let token = keychain.retrieve(key: KeychainStore.agentTokenKey(serverId: server.id))
        let client: any AgentClient
        switch server.type {
        case .openclaw:
            client = OpenClawClient(serverId: server.id, url: url, token: token)
        case .hermes:
            client = HermesClient(serverId: server.id, baseURL: url, token: token, agentName: server.name)
        }
        await agentClientManager.register(client: client)
        try? await client.connect()
    }

    // MARK: - Chat Window

    func toggleChatWindow() {
        if let window = chatWindow, window.isVisible {
            window.orderOut(nil)
            return
        }
        Task {
            let agents = (try? await agentClientManager.allEnabledAgents()) ?? []
            self.chatAgents = agents
            let chatView = ChatView(agents: agents, clientManager: agentClientManager)
            let hostingController = NSHostingController(rootView: chatView)
            if chatWindow == nil {
                chatWindow = ChatWindow(contentView: hostingController.view)
            } else {
                chatWindow?.contentView = hostingController.view
            }
            chatWindow?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        let hk = HotkeyManager(voiceTrigger: currentTrigger, chatTrigger: chatTrigger)
        hk.onKeyDown = { [weak self] in
            Task { @MainActor in self?.startListening() }
        }
        hk.onKeyUp = { [weak self] in
            Task { @MainActor in self?.stopListeningAndProcess() }
        }
        hk.onChatToggle = { [weak self] in
            Task { @MainActor in self?.toggleChatWindow() }
        }
        do {
            try hk.start()
            self.hotkeyManager = hk
        } catch {
            voxState = .error("Hotkey setup failed: \(error.localizedDescription)")
        }
    }

    private func reloadHotkey() {
        hotkeyManager?.stop()
        hotkeyManager = nil
        setupHotkey()
    }

    private func startListening() {
        voxState = .listening
        do { try audioManager?.startRecording() }
        catch { voxState = .error("Recording failed: \(error.localizedDescription)") }
    }

    private func stopListeningAndProcess() {
        guard let audioManager else { return }
        let audio = audioManager.stopRecording()
        guard audio.duration > 0.1 else { voxState = .idle; return }
        voxState = .processing
        Task {
            do {
                if activeBackend == nil { activeBackend = createBackend() }
                guard let backend = activeBackend else { voxState = .error("No STT backend configured"); return }
                let result = try await backend.transcribe(audio: audio)
                let formatted = rawFormatter?.format(result.text) ?? result.text
                lastTranscript = formatted
                if let injector = textInjector {
                    let injResult = await injector.inject(text: formatted, strategy: .clipboard, autoEnter: autoEnterEnabled)
                    if injResult.success {
                        voxState = .success
                    } else {
                        voxState = .error("Inject: \(injResult.error ?? "unknown")")
                    }
                } else {
                    voxState = .error("No injector")
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if case .success = voxState { voxState = .idle }
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
            guard let scriptPath = Bundle.main.path(forResource: "run", ofType: "sh", inDirectory: "whisper-sidecar") else {
                voxState = .error("Missing whisper sidecar script in bundle")
                return nil
            }
            let modelPath = appSupport.appendingPathComponent("Models/ggml-small.bin").path
            return WhisperCppBackend(scriptPath: scriptPath, modelPath: modelPath)
        case "mlx-whisper":
            guard let scriptPath = Bundle.main.path(forResource: "server", ofType: "py", inDirectory: "mlx-whisper-sidecar") else {
                voxState = .error("Missing MLX sidecar script in bundle")
                return nil
            }
            return MLXWhisperBackend(scriptPath: scriptPath)
        default: return nil
        }
    }
}
```

- [ ] **Step 2: Build and fix any compilation errors**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift build 2>&1 | tail -30`
Expected: Clean build. If there are errors, fix them — the most likely issues are missing imports or type mismatches.

- [ ] **Step 3: Run all tests**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift test 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add VoxOpsApp/AppState.swift
git commit -m "feat: wire agent client manager, chat window, and dual hotkey into AppState"
```

---

## Task 10: Final Integration Test — Build & Verify

- [ ] **Step 1: Full clean build**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift package clean && swift build 2>&1 | tail -30`
Expected: Clean build with no errors.

- [ ] **Step 2: Run full test suite**

Run: `cd /Users/eric/conductor/workspaces/vox-ops/bozeman && swift test 2>&1 | tail -30`
Expected: All tests pass.

- [ ] **Step 3: Commit any final fixes if needed**

If any fixes were required, commit them:
```bash
git add -A && git commit -m "fix: resolve compilation issues from agent chat integration"
```
