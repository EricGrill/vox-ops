import Foundation
import CoreGraphics
import ApplicationServices

public final class HotkeyManager: @unchecked Sendable {
    public typealias KeyHandler = @Sendable () -> Void

    private let keyCode: CGKeyCode
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let lock = NSLock()

    public var onKeyDown: KeyHandler?
    public var onKeyUp: KeyHandler?

    public init(keyCode: CGKeyCode = 0x31) {
        self.keyCode = keyCode
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard AXIsProcessTrusted() else { throw HotkeyError.accessibilityNotGranted }

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
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
        guard eventKeyCode == keyCode else { return Unmanaged.passUnretained(event) }

        switch type {
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                onKeyDown?()
            }
            return nil // consume
        case .keyUp:
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
