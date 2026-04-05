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
        // Capture handler if active — will invoke after lock is fully released
        let wasActive = isVoiceActive
        let handler = wasActive ? onKeyUp : nil
        isVoiceActive = false
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
        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let modifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

        // If voice is active, check if voice modifiers were released → trigger key up
        if isVoiceActive && type == .flagsChanged {
            let requiredModifiers = voiceTrigger.cgEventFlags
            let activeModifiers = event.flags.intersection(modifierMask)
            if !activeModifiers.contains(requiredModifiers) {
                isVoiceActive = false
                onKeyUp?()
            }
            return Unmanaged.passUnretained(event)
        }

        // Filter auto-repeat events
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        // Check chat trigger keyDown first (single press toggles, consume event)
        if let chat = chatTrigger, type == .keyDown, CGKeyCode(chat.keyCode) == eventKeyCode {
            let requiredModifiers = chat.cgEventFlags
            if requiredModifiers.isEmpty || event.flags.intersection(modifierMask).contains(requiredModifiers) {
                if !isAutoRepeat {
                    onChatToggle?()
                }
                return nil // consume
            }
        }

        // Check voice trigger keyDown/keyUp (push-to-talk hold, consume event)
        let voiceKeyCode = CGKeyCode(voiceTrigger.keyCode)
        guard eventKeyCode == voiceKeyCode else { return Unmanaged.passUnretained(event) }

        switch type {
        case .keyDown:
            let requiredModifiers = voiceTrigger.cgEventFlags
            if !requiredModifiers.isEmpty {
                let activeModifiers = event.flags.intersection(modifierMask)
                guard activeModifiers.contains(requiredModifiers) else {
                    return Unmanaged.passUnretained(event)
                }
            }
            if !isAutoRepeat {
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
