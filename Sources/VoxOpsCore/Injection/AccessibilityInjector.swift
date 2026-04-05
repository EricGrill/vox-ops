import Foundation
import AppKit
import ApplicationServices

public final class AccessibilityInjector: Sendable {
    public init() {}

    public func inject(text: String) async -> InjectionResult {
        guard AXIsProcessTrusted() else {
            return InjectionResult(success: false, strategy: .accessibility, error: "Accessibility permission not granted")
        }
        guard let focusedApp = NSWorkspace.shared.frontmostApplication else {
            return InjectionResult(success: false, strategy: .accessibility, error: "No frontmost application")
        }
        let appElement = AXUIElementCreateApplication(focusedApp.processIdentifier)
        var focusedElement: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard focusErr == .success, let element = focusedElement else {
            return InjectionResult(success: false, strategy: .accessibility, error: "Cannot get focused element")
        }
        let axElement = element as! AXUIElement

        // Try inserting at selected text range
        var selectedRange: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRange)
        if rangeErr == .success {
            let setErr = AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            if setErr == .success {
                return InjectionResult(success: true, strategy: .accessibility)
            }
        }

        // Fallback: append to AXValue
        var currentValue: CFTypeRef?
        let valErr = AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &currentValue)
        if valErr == .success, let current = currentValue as? String {
            let newValue = current + text
            let setErr = AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, newValue as CFTypeRef)
            if setErr == .success {
                return InjectionResult(success: true, strategy: .accessibility)
            }
        }

        return InjectionResult(success: false, strategy: .accessibility, error: "Could not set text via AX API")
    }
}
