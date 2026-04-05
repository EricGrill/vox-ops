# Hotkey Configuration & Auto-Enter Design

## Goal

Allow users to configure the push-to-talk trigger (keyboard combo or mouse side button) via the Settings UI, with live reload. Add an optional auto-enter toggle that sends Return after text injection.

## Trigger Model

A `HotkeyTrigger` enum represents the push-to-talk binding:

```swift
enum HotkeyTrigger: Codable, Equatable {
    case keyboard(keyCode: UInt16, modifiers: [ModifierKey])
    case mouseButton(buttonNumber: Int)
}

enum ModifierKey: String, Codable, CaseIterable, Comparable {
    case command, option, control, shift

    var cgEventFlag: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .option:  return .maskAlternate
        case .control: return .maskControl
        case .shift:   return .maskShift
        }
    }

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option:  return "⌥"
        case .control: return "⌃"
        case .shift:   return "⇧"
        }
    }
}
```

**Constraints:**
- Keyboard triggers require at least one modifier (prevents capturing plain keys)
- Mouse buttons 3+ only (not left/right click)
- Default trigger: `keyboard(keyCode: 0x31, modifiers: [.command, .option])` (⌥⌘Space)
- Serialized as JSON string in SettingsStore under key `"hotkey_trigger"`
- `modifiers` is an array (not Set) sorted by `Comparable` conformance for deterministic encoding

**Computed helpers on HotkeyTrigger:**
- `cgEventFlags` — combines all modifier `cgEventFlag` values into a single `CGEventFlags`
- `displayString` — human-readable label ("⌥⌘Space", "Mouse Button 4")
- `static let `default`` — the default ⌥⌘Space trigger
- `validate()` — returns nil if valid, error string if not (no modifiers, reserved combo, etc.)

## HotkeyManager Refactor

HotkeyManager currently accepts `keyCode: CGKeyCode` and `requiredModifiers: CGEventFlags`. Refactor to accept `HotkeyTrigger` instead.

**CGEvent mask changes:**
- Keyboard trigger: `keyDown | keyUp | flagsChanged` (current behavior)
- Mouse trigger: `otherMouseDown | otherMouseUp` (for buttons 3+)

**Event handling:**
- Keyboard: existing logic — check keyCode + modifiers on keyDown, track `isActive` state, fire onKeyUp on key release or modifier release
- Mouse: check `event.getIntegerValueField(.mouseEventButtonNumber)` matches configured button number, fire onKeyDown/onKeyUp on otherMouseDown/otherMouseUp

**Memory safety:** The CGEvent tap callback uses `Unmanaged.passUnretained(self)` to pass `self` as a C pointer. During live reload, the old HotkeyManager instance could be released while the callback is still registered. Fix: use `Unmanaged.passRetained(self)` when creating the tap and `Unmanaged.release` in `stop()` after the tap is disabled and the run loop source is removed. This ensures the instance stays alive until the tap is fully torn down.

**Active state cleanup on stop():** If `isActive` is true when `stop()` is called (user is holding the key during a settings change), `stop()` must fire `onKeyUp?()` before tearing down the tap. This prevents `AppState.voxState` from getting stuck in `.listening`.

## Settings UI

The General tab's Hotkey section becomes interactive. The settings window frame height increases from 300 to 400 to accommodate the new controls.

### Current Binding Display
- Text showing current trigger in human-readable form: "⌥⌘Space" or "Mouse Button 4"

### Keyboard Recorder
- Button labeled "Record Keyboard Shortcut..."
- Enters recording mode on click: label changes to "Press your shortcut..."
- Uses NSEvent.addLocalMonitorForEvents to capture the next key combo (modifier + key) within the Settings window
- Validates: must include at least one modifier, rejects reserved combos (see Reserved Shortcuts below)
- On success: saves the new trigger, exits recording mode, shows the new binding
- Escape cancels recording
- If the system intercepts a shortcut before the recorder sees it (e.g. ⌘H, ⌘M), no keyDown arrives — recorder stays in recording mode, user can try another combo

### Mouse Button Picker
- `Picker` with options: "None", "Button 3 (Middle)", "Button 4 (Back)", "Button 5 (Forward)"
- Selecting a mouse button (not "None") saves it as the trigger and clears any keyboard binding
- Selecting "None" is a no-op — keeps the current trigger unchanged
- Recording a keyboard shortcut sets picker back to "None"
- Keyboard and mouse triggers are mutually exclusive

### Reset to Default
- Button that restores ⌥⌘Space

### After Injection Section
- Toggle for auto-enter (see below)

## Auto-Enter Toggle

```swift
Toggle("Press Enter after pasting text", isOn: $autoEnterEnabled)
Text("Sends Return keystroke after text is injected.")
    .font(.caption).foregroundStyle(.tertiary)
```

- Persisted in SettingsStore as `"auto_enter"` (string "true"/"false", default "false")
- The `autoEnter` parameter is added to `TextInjector.inject(text:strategy:autoEnter:)` which passes it through to `ClipboardInjector.inject(text:autoEnter:)`
- When enabled, after the ⌘V paste CGEvent completes (after the 300ms wait), the injector sends an additional Return keystroke (keyCode `0x24` / `kVK_Return`) via CGEvent posted to `cgAnnotatedSessionEventTap`
- Note: currently AppState hardcodes `.clipboard` strategy, so autoEnter always flows through ClipboardInjector. If strategy changes to `.auto` in the future, AccessibilityInjector would also need an autoEnter path.
- Shown in Settings under a new "After Injection" section in the General tab

## Live Reload Flow

1. User changes trigger in Settings UI
2. New `HotkeyTrigger` serialized as JSON, saved to SettingsStore under `"hotkey_trigger"`
3. AppState.selectedTrigger published property updates
4. AppState calls `hotkeyManager.stop()` — this fires `onKeyUp` if active, then tears down the tap (releasing the retained self pointer)
5. AppState creates new HotkeyManager with new trigger
6. AppState calls `hotkeyManager.start()` to install new tap
7. If `start()` throws (accessibility permission revoked), AppState sets `voxState = .error(...)` — same error handling as initial setup
8. UI reflects the new binding immediately

On app launch, AppState reads `"hotkey_trigger"` from SettingsStore. If absent, uses default (⌥⌘Space).

## Files Affected

| File | Change |
|------|--------|
| `Sources/VoxOpsCore/Hotkey/HotkeyManager.swift` | Accept `HotkeyTrigger`, handle mouse events, retained self, stop() cleanup |
| `Sources/VoxOpsCore/Hotkey/HotkeyTrigger.swift` | New — trigger enum, modifier key enum with CGEventFlags mapping |
| `Sources/VoxOpsCore/Injection/TextInjector.swift` | Add `autoEnter` parameter, pass through to injectors |
| `Sources/VoxOpsCore/Injection/ClipboardInjector.swift` | Accept `autoEnter` flag, send Return (0x24) after paste |
| `Sources/VoxOpsCore/Storage/SettingsStore.swift` | No changes needed (already generic key-value) |
| `VoxOpsApp/AppState.swift` | Load trigger + autoEnter from settings, live reload on change |
| `VoxOpsApp/Views/SettingsView.swift` | Recorder widget, mouse picker, auto-enter toggle, taller frame |
| `Tests/VoxOpsCoreTests/HotkeyTriggerTests.swift` | New — serialization round-trips, validation, modifier mapping |

## Reserved Keyboard Shortcuts

The recorder rejects these shortcuts:
- ⌘Q (Quit)
- ⌘W (Close window)
- ⌘Tab (App switcher)
- ⌘Space (Spotlight)
- ⌘H (Hide)
- ⌘M (Minimize)

Note: Some system shortcuts (⌘⌥Esc, ⌘⌥F5) are intercepted by macOS before any event tap or local monitor can see them. These don't need explicit rejection — the recorder simply won't receive them and stays in recording mode.

If the user presses a rejected combo, the recorder shows a brief "Reserved shortcut" message and stays in recording mode.
