// Sources/VoxOpsCore/Hotkey/HotkeyManager.swift
import Foundation
import CoreGraphics
import ApplicationServices

public final class HotkeyManager: @unchecked Sendable {
    public typealias KeyHandler = @Sendable () -> Void

    private let voiceTrigger: HotkeyTrigger
    private var chatTrigger: HotkeyTrigger?
    private var toggleTrigger: HotkeyTrigger?
    private var isVoiceActive = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retainedSelf: Unmanaged<HotkeyManager>?
    private let lock = NSLock()

    public var onKeyDown: KeyHandler?
    public var onKeyUp: KeyHandler?
    public var onChatToggle: KeyHandler?
    public var onToggleListening: KeyHandler?

    public init(
        voiceTrigger: HotkeyTrigger = .default,
        chatTrigger: HotkeyTrigger? = nil,
        toggleTrigger: HotkeyTrigger? = nil
    ) {
        self.voiceTrigger = voiceTrigger
        self.chatTrigger = chatTrigger
        self.toggleTrigger = toggleTrigger
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
        let modifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let activeModifiers = event.flags.intersection(modifierMask)
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        // If voice is active via PTT, check if voice modifiers were released
        if isVoiceActive && type == .flagsChanged {
            let requiredModifiers = voiceTrigger.cgEventFlags
            if !activeModifiers.contains(requiredModifiers) {
                isVoiceActive = false
                onKeyUp?()
            }
            return Unmanaged.passUnretained(event)
        }

        // Toggle-to-talk: single press starts/stops listening
        if let toggle = toggleTrigger, type == .keyDown, CGKeyCode(toggle.keyCode) == eventKeyCode {
            let required = toggle.cgEventFlags
            if required.isEmpty || activeModifiers.contains(required) {
                if !isAutoRepeat {
                    if isVoiceActive {
                        isVoiceActive = false
                        onKeyUp?()
                    } else {
                        isVoiceActive = true
                        onToggleListening?()
                    }
                }
                return nil
            }
        }

        // Chat trigger: single press toggles chat window
        if let chat = chatTrigger, type == .keyDown, CGKeyCode(chat.keyCode) == eventKeyCode {
            let required = chat.cgEventFlags
            if required.isEmpty || activeModifiers.contains(required) {
                if !isAutoRepeat {
                    onChatToggle?()
                }
                return nil
            }
        }

        // Voice trigger: push-to-talk hold
        let voiceKeyCode = CGKeyCode(voiceTrigger.keyCode)
        guard eventKeyCode == voiceKeyCode else { return Unmanaged.passUnretained(event) }

        switch type {
        case .keyDown:
            let required = voiceTrigger.cgEventFlags
            if !required.isEmpty {
                guard activeModifiers.contains(required) else {
                    return Unmanaged.passUnretained(event)
                }
            }
            if !isAutoRepeat {
                isVoiceActive = true
                onKeyDown?()
            }
            return nil
        case .keyUp:
            guard isVoiceActive else { return Unmanaged.passUnretained(event) }
            isVoiceActive = false
            onKeyUp?()
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

public enum HotkeyError: Error, Sendable {
    case accessibilityNotGranted
    case cannotCreateEventTap
}
