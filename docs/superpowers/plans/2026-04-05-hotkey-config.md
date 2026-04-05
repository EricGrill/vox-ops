# Hotkey Configuration & Auto-Enter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to configure their push-to-talk trigger (keyboard combo or mouse side button) with live reload, plus an optional auto-enter toggle.

**Architecture:** New `HotkeyTrigger` enum encapsulates trigger types (keyboard/mouse). HotkeyManager is refactored to accept it. Settings UI gets a keyboard recorder and mouse button picker. Changes persist to SettingsStore as JSON and apply immediately via event tap teardown/recreate.

**Tech Stack:** Swift 5.9, SwiftUI, CoreGraphics (CGEvent), ApplicationServices, GRDB

**Spec:** `docs/superpowers/specs/2026-04-05-hotkey-config-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `Sources/VoxOpsCore/Hotkey/HotkeyTrigger.swift` | NEW — `HotkeyTrigger` enum, `ModifierKey` enum, serialization, validation, display strings |
| `Sources/VoxOpsCore/Hotkey/HotkeyManager.swift` | MODIFY — Accept `HotkeyTrigger`, handle mouse events, retained self pointer, stop() cleanup |
| `Sources/VoxOpsCore/Injection/ClipboardInjector.swift` | MODIFY — Accept `autoEnter` flag, send Return after paste |
| `Sources/VoxOpsCore/Injection/TextInjector.swift` | MODIFY — Pass `autoEnter` through to injectors |
| `VoxOpsApp/AppState.swift` | MODIFY — Load/save trigger + autoEnter settings, live reload hotkey |
| `VoxOpsApp/Views/SettingsView.swift` | MODIFY — Keyboard recorder, mouse picker, auto-enter toggle, taller frame |
| `Tests/VoxOpsCoreTests/HotkeyTriggerTests.swift` | NEW — Serialization round-trips, validation, modifier mapping |

---

### Task 1: HotkeyTrigger Model

**Files:**
- Create: `Sources/VoxOpsCore/Hotkey/HotkeyTrigger.swift`
- Create: `Tests/VoxOpsCoreTests/HotkeyTriggerTests.swift`

- [ ] **Step 1: Write tests for HotkeyTrigger**

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
        let trigger = HotkeyTrigger.keyboard(keyCode: 0x31, modifiers: [.command, .option])
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(HotkeyTrigger.self, from: data)
        #expect(decoded == trigger)
    }

    @Test("mouse button trigger JSON round-trip")
    func mouseRoundTrip() throws {
        let trigger = HotkeyTrigger.mouseButton(buttonNumber: 4)
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(HotkeyTrigger.self, from: data)
        #expect(decoded == trigger)
    }

    @Test("modifiers encode in sorted order")
    func sortedModifiers() throws {
        let trigger = HotkeyTrigger.keyboard(keyCode: 0x31, modifiers: [.shift, .command, .option])
        let data = try JSONEncoder().encode(trigger)
        let json = String(data: data, encoding: .utf8)!
        let commandIdx = json.range(of: "command")!.lowerBound
        let optionIdx = json.range(of: "option")!.lowerBound
        let shiftIdx = json.range(of: "shift")!.lowerBound
        #expect(commandIdx < optionIdx)
        #expect(optionIdx < shiftIdx)
    }

    @Test("default trigger is option-command-space")
    func defaultTrigger() {
        let trigger = HotkeyTrigger.default
        if case .keyboard(let keyCode, let modifiers) = trigger {
            #expect(keyCode == 0x31)
            #expect(modifiers == [.command, .option])
        } else {
            Issue.record("Expected keyboard trigger")
        }
    }

    @Test("keyboard display string shows modifier symbols")
    func keyboardDisplayString() {
        let trigger = HotkeyTrigger.keyboard(keyCode: 0x31, modifiers: [.command, .option])
        #expect(trigger.displayString == "⌥⌘Space")
    }

    @Test("mouse button display string")
    func mouseDisplayString() {
        #expect(HotkeyTrigger.mouseButton(buttonNumber: 3).displayString == "Mouse Button 3 (Middle)")
        #expect(HotkeyTrigger.mouseButton(buttonNumber: 4).displayString == "Mouse Button 4 (Back)")
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
        let trigger = HotkeyTrigger.keyboard(keyCode: 0x31, modifiers: [.command, .option])
        let flags = trigger.cgEventFlags
        #expect(flags.contains(.maskCommand))
        #expect(flags.contains(.maskAlternate))
    }

    @Test("validation rejects keyboard with no modifiers")
    func rejectsNoModifiers() {
        let trigger = HotkeyTrigger.keyboard(keyCode: 0x31, modifiers: [])
        #expect(trigger.validate() != nil)
    }

    @Test("validation rejects reserved shortcut cmd-Q")
    func rejectsReserved() {
        let trigger = HotkeyTrigger.keyboard(keyCode: 0x0C, modifiers: [.command]) // ⌘Q
        #expect(trigger.validate() != nil)
    }

    @Test("validation accepts valid keyboard trigger")
    func acceptsValid() {
        let trigger = HotkeyTrigger.keyboard(keyCode: 0x31, modifiers: [.command, .option])
        #expect(trigger.validate() == nil)
    }

    @Test("validation rejects mouse button 0, 1, and 2")
    func rejectsLeftRightMiddle() {
        #expect(HotkeyTrigger.mouseButton(buttonNumber: 0).validate() != nil)
        #expect(HotkeyTrigger.mouseButton(buttonNumber: 1).validate() != nil)
        #expect(HotkeyTrigger.mouseButton(buttonNumber: 2).validate() != nil)
    }

    @Test("validation accepts mouse button 3+")
    func acceptsMouseSide() {
        #expect(HotkeyTrigger.mouseButton(buttonNumber: 3).validate() == nil)
        #expect(HotkeyTrigger.mouseButton(buttonNumber: 4).validate() == nil)
        #expect(HotkeyTrigger.mouseButton(buttonNumber: 5).validate() == nil)
    }

    @Test("mouse button 5 display string shows Forward")
    func mouseForwardDisplayString() {
        let trigger = HotkeyTrigger.mouseButton(buttonNumber: 5)
        #expect(trigger.displayString == "Mouse Button 5 (Forward)")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HotkeyTrigger 2>&1 | tail -5`
Expected: FAIL — `HotkeyTrigger` type not found

- [ ] **Step 3: Implement HotkeyTrigger**

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

    // Comparable — sort order: control, option, shift, command (standard macOS menu bar order)
    public static func < (lhs: ModifierKey, rhs: ModifierKey) -> Bool {
        let order: [ModifierKey] = [.control, .option, .shift, .command]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

public enum HotkeyTrigger: Codable, Equatable, Sendable {
    case keyboard(keyCode: UInt16, modifiers: [ModifierKey])
    case mouseButton(buttonNumber: Int)

    public static let `default` = HotkeyTrigger.keyboard(keyCode: 0x31, modifiers: [.command, .option])

    /// Combined CGEventFlags for all modifiers (keyboard triggers only, empty for mouse)
    public var cgEventFlags: CGEventFlags {
        switch self {
        case .keyboard(_, let modifiers):
            var flags = CGEventFlags()
            for mod in modifiers { flags.insert(mod.cgEventFlag) }
            return flags
        case .mouseButton:
            return []
        }
    }

    /// Human-readable display string
    public var displayString: String {
        switch self {
        case .keyboard(let keyCode, let modifiers):
            let modStr = modifiers.sorted().map(\.symbol).joined()
            let keyName = Self.keyCodeName(keyCode)
            return modStr + keyName
        case .mouseButton(let num):
            let label: String
            switch num {
            case 3: label = "Middle"
            case 4: label = "Back"
            case 5: label = "Forward"
            default: label = "Button \(num)"
            }
            return "Mouse Button \(num) (\(label))"
        }
    }

    /// Returns nil if valid, error string if invalid
    public func validate() -> String? {
        switch self {
        case .keyboard(let keyCode, let modifiers):
            if modifiers.isEmpty { return "Keyboard shortcut requires at least one modifier" }
            if isReserved(keyCode: keyCode, modifiers: Set(modifiers)) {
                return "This shortcut is reserved by the system"
            }
            return nil
        case .mouseButton(let num):
            if num < 3 { return "Left, right, and middle mouse buttons cannot be used" }
            return nil
        }
    }

    // MARK: - Codable with sorted modifiers

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .keyboard(let keyCode, let modifiers):
            try container.encode(KeyboardPayload(keyCode: keyCode, modifiers: modifiers.sorted()))
        case .mouseButton(let num):
            try container.encode(MousePayload(buttonNumber: num))
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let kb = try? container.decode(KeyboardPayload.self) {
            self = .keyboard(keyCode: kb.keyCode, modifiers: kb.modifiers.sorted())
        } else {
            let mouse = try container.decode(MousePayload.self)
            self = .mouseButton(buttonNumber: mouse.buttonNumber)
        }
    }

    private struct KeyboardPayload: Codable {
        let keyCode: UInt16
        let modifiers: [ModifierKey]
    }

    private struct MousePayload: Codable {
        let buttonNumber: Int
    }

    // MARK: - Private

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
            (0x31, [.command]),            // ⌘Space (Spotlight)
            (0x04, [.command]),            // ⌘H (Hide)
            (0x2E, [.command]),            // ⌘M (Minimize)
        ]
        return reserved.contains { $0.0 == keyCode && $0.1 == modifiers }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HotkeyTrigger 2>&1 | tail -5`
Expected: All 13 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/VoxOpsCore/Hotkey/HotkeyTrigger.swift Tests/VoxOpsCoreTests/HotkeyTriggerTests.swift
git commit -m "feat: add HotkeyTrigger model with validation and serialization"
```

---

### Task 2: Refactor HotkeyManager to Accept HotkeyTrigger

**Files:**
- Modify: `Sources/VoxOpsCore/Hotkey/HotkeyManager.swift`

- [ ] **Step 1: Refactor HotkeyManager init and event mask**

Replace the entire file:

```swift
// Sources/VoxOpsCore/Hotkey/HotkeyManager.swift
import Foundation
import CoreGraphics
import ApplicationServices

public final class HotkeyManager: @unchecked Sendable {
    public typealias KeyHandler = @Sendable () -> Void

    private let trigger: HotkeyTrigger
    private var isActive = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retainedSelf: Unmanaged<HotkeyManager>?
    private let lock = NSLock()

    public var onKeyDown: KeyHandler?
    public var onKeyUp: KeyHandler?

    public init(trigger: HotkeyTrigger = .default) {
        self.trigger = trigger
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard AXIsProcessTrusted() else { throw HotkeyError.accessibilityNotGranted }

        let eventMask: Int
        switch trigger {
        case .keyboard:
            eventMask = (1 << CGEventType.keyDown.rawValue)
                      | (1 << CGEventType.keyUp.rawValue)
                      | (1 << CGEventType.flagsChanged.rawValue)
        case .mouseButton:
            eventMask = (1 << CGEventType.otherMouseDown.rawValue)
                      | (1 << CGEventType.otherMouseUp.rawValue)
        }

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
        // Capture handler if active — will invoke after lock is fully released
        let wasActive = isActive
        let handler = wasActive ? onKeyUp : nil
        isActive = false
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        // Release the retained self pointer
        let retained = retainedSelf
        retainedSelf = nil
        lock.unlock()
        retained?.release()
        // Fire onKeyUp after lock is released to prevent deadlock if handler calls back into us
        if wasActive { handler?() }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch trigger {
        case .keyboard(let keyCode, _):
            return handleKeyboardEvent(keyCode: CGKeyCode(keyCode), type: type, event: event)
        case .mouseButton(let buttonNumber):
            return handleMouseEvent(buttonNumber: buttonNumber, type: type, event: event)
        }
    }

    // MARK: - Keyboard handling

    private func handleKeyboardEvent(keyCode: CGKeyCode, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let requiredModifiers = trigger.cgEventFlags

        // If active, check if modifiers were released → trigger key up
        if isActive && type == .flagsChanged {
            let mask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
            let activeModifiers = event.flags.intersection(mask)
            if !activeModifiers.contains(requiredModifiers) {
                isActive = false
                onKeyUp?()
            }
            return Unmanaged.passUnretained(event)
        }

        guard eventKeyCode == keyCode else { return Unmanaged.passUnretained(event) }

        switch type {
        case .keyDown:
            if !requiredModifiers.isEmpty {
                let mask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
                let activeModifiers = event.flags.intersection(mask)
                guard activeModifiers.contains(requiredModifiers) else {
                    return Unmanaged.passUnretained(event)
                }
            }
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                isActive = true
                onKeyDown?()
            }
            return nil // consume
        case .keyUp:
            guard isActive else { return Unmanaged.passUnretained(event) }
            isActive = false
            onKeyUp?()
            return nil // consume
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Mouse handling

    private func handleMouseEvent(buttonNumber: Int, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let eventButton = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        guard eventButton == buttonNumber else { return Unmanaged.passUnretained(event) }

        switch type {
        case .otherMouseDown:
            isActive = true
            onKeyDown?()
            return nil // consume
        case .otherMouseUp:
            guard isActive else { return Unmanaged.passUnretained(event) }
            isActive = false
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

- [ ] **Step 2: Run all tests to verify nothing broke**

Run: `swift test 2>&1 | tail -5`
Expected: All tests PASS (WhisperCppBackendTests should still pass since HotkeyManager isn't tested directly there)

- [ ] **Step 3: Commit**

```bash
git add Sources/VoxOpsCore/Hotkey/HotkeyManager.swift
git commit -m "refactor: HotkeyManager accepts HotkeyTrigger, adds mouse support and memory safety"
```

---

### Task 3: Auto-Enter in Injection Layer

**Files:**
- Modify: `Sources/VoxOpsCore/Injection/ClipboardInjector.swift`
- Modify: `Sources/VoxOpsCore/Injection/TextInjector.swift`

- [ ] **Step 1: Add autoEnter parameter to ClipboardInjector**

In `Sources/VoxOpsCore/Injection/ClipboardInjector.swift`, replace the `inject` method signature and add Return keystroke after paste:

```swift
    public func inject(text: String, autoEnter: Bool = false) async -> InjectionResult {
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> (String, Data)? in
            guard let type = item.types.first, let data = item.data(forType: type) else { return nil }
            return (type.rawValue, data)
        } ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Wait for clipboard to settle and target app to have focus
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Simulate ⌘V via CGEvent — post to cgAnnotatedSessionEventTap for cross-app delivery
        let src = CGEventSource(stateID: .combinedSessionState)
        if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) {
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cgAnnotatedSessionEventTap)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
        }

        // Wait for paste to complete
        try? await Task.sleep(nanoseconds: 300_000_000)

        // Send Return keystroke if auto-enter is enabled
        if autoEnter {
            let returnKeyCode: CGKeyCode = 0x24 // kVK_Return
            if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: returnKeyCode, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: src, virtualKey: returnKeyCode, keyDown: false) {
                keyDown.post(tap: .cgAnnotatedSessionEventTap)
                keyUp.post(tap: .cgAnnotatedSessionEventTap)
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        // Restore previous clipboard contents
        pasteboard.clearContents()
        for (typeRaw, data) in savedItems {
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(typeRaw))
        }

        return InjectionResult(success: true, strategy: .clipboard)
    }
```

- [ ] **Step 2: Add autoEnter parameter to TextInjector**

In `Sources/VoxOpsCore/Injection/TextInjector.swift`, update the `inject` method:

```swift
    public func inject(text: String, strategy: InjectionStrategy = .auto, autoEnter: Bool = false) async -> InjectionResult {
        switch strategy {
        case .accessibility:
            return await accessibilityInjector.inject(text: text)
        case .clipboard:
            return await clipboardInjector.inject(text: text, autoEnter: autoEnter)
        case .auto:
            let axResult = await accessibilityInjector.inject(text: text)
            if axResult.success { return axResult }
            return await clipboardInjector.inject(text: text, autoEnter: autoEnter)
        }
    }
```

- [ ] **Step 3: Run tests to verify nothing broke**

Run: `swift test 2>&1 | tail -5`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/VoxOpsCore/Injection/ClipboardInjector.swift Sources/VoxOpsCore/Injection/TextInjector.swift
git commit -m "feat: add autoEnter parameter to injection layer"
```

---

### Task 4: AppState — Load Settings and Live Reload

**Files:**
- Modify: `VoxOpsApp/AppState.swift`

- [ ] **Step 1: Add published properties and settings loading**

Add new properties and refactor `setup()` and `setupHotkey()`:

```swift
@MainActor
final class AppState: ObservableObject {
    @Published var voxState: VoxState = .idle
    @Published var lastTranscript: String = ""
    @Published var selectedBackend: String = "whisper.cpp"
    @Published var isSettingsOpen = false
    @Published var currentTrigger: HotkeyTrigger = .default
    @Published var autoEnterEnabled: Bool = false

    private var database: Database?
    private var settingsStore: SettingsStore?
    private var audioManager: AudioManager?
    private var hotkeyManager: HotkeyManager?
    private var textInjector: TextInjector?
    private var rawFormatter: RawFormatter?
    private var activeBackend: (any STTBackend)?

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
        } catch {
            voxState = .error("Setup failed: \(error.localizedDescription)")
        }
    }

    private func loadSettings() {
        guard let store = settingsStore else { return }
        // Load trigger
        if let json = try? store.getString("hotkey_trigger"),
           let data = json.data(using: .utf8),
           let trigger = try? JSONDecoder().decode(HotkeyTrigger.self, from: data) {
            currentTrigger = trigger
        }
        // Load auto-enter
        if let value = try? store.getString("auto_enter") {
            autoEnterEnabled = value == "true"
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

    func saveAutoEnter(_ enabled: Bool) {
        guard let store = settingsStore else { return }
        try? store.setString("auto_enter", value: enabled ? "true" : "false")
        autoEnterEnabled = enabled
    }

    private func setupHotkey() {
        let hk = HotkeyManager(trigger: currentTrigger)
        hk.onKeyDown = { [weak self] in
            Task { @MainActor in self?.startListening() }
        }
        hk.onKeyUp = { [weak self] in
            Task { @MainActor in self?.stopListeningAndProcess() }
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
```

Also update `stopListeningAndProcess` to pass `autoEnterEnabled` to the injector:

```swift
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
```

The `startListening()` and `createBackend()` methods remain unchanged.

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds (SPM only builds VoxOpsCore, not VoxOpsApp — use xcodebuild for full check)

Run: `xcodegen generate && xcodebuild -project VoxOps.xcodeproj -scheme VoxOpsApp -configuration Debug build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add VoxOpsApp/AppState.swift
git commit -m "feat: AppState loads hotkey trigger and auto-enter settings with live reload"
```

---

### Task 5: Settings View — Recorder, Mouse Picker, Auto-Enter Toggle

**Files:**
- Modify: `VoxOpsApp/Views/SettingsView.swift`

- [ ] **Step 1: Replace SettingsView with full implementation**

```swift
import SwiftUI
import VoxOpsCore

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selectedBackend = "whisper.cpp"
    @State private var isRecording = false
    @State private var recordingError: String?
    @State private var selectedMouseButton = 0 // 0 = None

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            audioTab.tabItem { Label("Audio", systemImage: "mic") }
        }
        .frame(width: 450, height: 400)
        .onAppear {
            selectedBackend = appState.selectedBackend
            if case .mouseButton(let num) = appState.currentTrigger {
                selectedMouseButton = num
            }
        }
    }

    private var generalTab: some View {
        Form {
            Section("Push-to-Talk Trigger") {
                Text("Current: \(appState.currentTrigger.displayString)")
                    .font(.headline)

                // Keyboard recorder
                Button(isRecording ? "Press your shortcut..." : "Record Keyboard Shortcut...") {
                    isRecording = true
                    recordingError = nil
                }
                .disabled(isRecording)
                .onKeyDown(isActive: $isRecording) { keyCode, modifiers in
                    // Escape cancels
                    if keyCode == 0x35 {
                        isRecording = false
                        recordingError = nil
                        return true
                    }
                    let modifierKeys = modifiers.toModifierKeys()
                    guard !modifierKeys.isEmpty else { return false } // Wait for modifier + key
                    let trigger = HotkeyTrigger.keyboard(keyCode: keyCode, modifiers: modifierKeys.sorted())
                    if let error = trigger.validate() {
                        recordingError = error
                        return true
                    }
                    isRecording = false
                    recordingError = nil
                    selectedMouseButton = 0
                    appState.saveTrigger(trigger)
                    return true
                }

                if let error = recordingError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }

                // Mouse button picker
                Picker("Or use mouse button", selection: $selectedMouseButton) {
                    Text("None").tag(0)
                    Text("Button 3 (Middle)").tag(3)
                    Text("Button 4 (Back)").tag(4)
                    Text("Button 5 (Forward)").tag(5)
                }
                .onChange(of: selectedMouseButton) { _, newValue in
                    guard newValue > 0 else { return }
                    let trigger = HotkeyTrigger.mouseButton(buttonNumber: newValue)
                    appState.saveTrigger(trigger)
                }

                Button("Reset to Default") {
                    selectedMouseButton = 0
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

/// View modifier that captures key events via NSEvent local monitor — only active when `isActive` is true
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
                            return nil // consumed
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

**Note:** The `.onKeyDown` modifier uses `NSEvent.addLocalMonitorForEvents` which only captures events within the app's own windows — perfect for the Settings window recorder. It does NOT interfere with the global CGEvent tap used for push-to-talk.

- [ ] **Step 2: Build the full app**

Run: `xcodegen generate && xcodebuild -project VoxOps.xcodeproj -scheme VoxOpsApp -configuration Debug build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run all tests**

Run: `swift test 2>&1 | tail -5`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add VoxOpsApp/Views/SettingsView.swift
git commit -m "feat: Settings UI with keyboard recorder, mouse picker, and auto-enter toggle"
```

---

### Task 6: Integration Test and Final Verification

**Files:**
- All modified files from previous tasks

- [ ] **Step 1: Run full test suite**

Run: `swift test 2>&1 | tail -10`
Expected: All tests PASS including new HotkeyTriggerTests

- [ ] **Step 2: Build and launch the app**

```bash
xcodegen generate
xcodebuild -project VoxOps.xcodeproj -scheme VoxOpsApp -configuration Debug build 2>&1 | tail -3
```
Expected: BUILD SUCCEEDED

Launch: `open /path/to/DerivedData/.../Debug/VoxOpsApp.app`

- [ ] **Step 3: Manual verification checklist**

1. Open Settings → General tab shows "Push-to-Talk Trigger" section
2. Current binding shows "⌥⌘Space"
3. Click "Record Keyboard Shortcut..." → shows "Press your shortcut..."
4. Press Escape → cancels recording
5. Record a new combo (e.g. ⌃⌥Space) → updates display, hotkey works immediately
6. Try recording ⌘Q → shows "reserved" error
7. Select Mouse Button 4 from picker → display updates, keyboard binding cleared
8. Click "Reset to Default" → reverts to ⌥⌘Space
9. Toggle "Press Enter after pasting text" on → dictate into a text field, Return is sent after text
10. Quit and relaunch → settings persist

- [ ] **Step 4: Commit all remaining changes**

```bash
git add -A
git commit -m "feat: configurable push-to-talk trigger with live reload and auto-enter"
```
