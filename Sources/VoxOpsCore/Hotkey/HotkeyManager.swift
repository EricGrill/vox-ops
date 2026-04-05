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
        return handleKeyboardEvent(keyCode: CGKeyCode(trigger.keyCode), type: type, event: event)
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
}

public enum HotkeyError: Error, Sendable {
    case accessibilityNotGranted
    case cannotCreateEventTap
}
