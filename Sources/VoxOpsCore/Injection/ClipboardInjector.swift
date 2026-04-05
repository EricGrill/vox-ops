import Foundation
import AppKit
import CoreGraphics

public final class ClipboardInjector: Sendable {
    public init() {}

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

    public static func buildPasteScript(text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        set the clipboard to "\(escaped)"
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
    }
}
