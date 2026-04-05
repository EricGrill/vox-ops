import Foundation
import CoreGraphics
import ApplicationServices

public final class HotkeyManager: @unchecked Sendable {
    public typealias KeyHandler = @Sendable () -> Void

    private let keyCode: CGKeyCode
    private let requiredModifiers: CGEventFlags
    private var isActive = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let lock = NSLock()

    public var onKeyDown: KeyHandler?
    public var onKeyUp: KeyHandler?

    public init(keyCode: CGKeyCode = 0x31, requiredModifiers: CGEventFlags = []) {
        self.keyCode = keyCode
        self.requiredModifiers = requiredModifiers
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard AXIsProcessTrusted() else { throw HotkeyError.accessibilityNotGranted }

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

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
            userInfo: selfPtr
        ) else { throw HotkeyError.cannotCreateEventTap }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        // If active (listening), check if modifiers were released → trigger key up
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
            // Check required modifiers on key down
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
            // Accept any Space keyUp while active, regardless of modifiers
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
