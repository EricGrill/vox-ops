import Foundation
import AppKit
import CoreGraphics

public final class ClipboardInjector: Sendable {
    public init() {}

    public func inject(text: String) async -> InjectionResult {
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> (String, Data)? in
            guard let type = item.types.first, let data = item.data(forType: type) else { return nil }
            return (type.rawValue, data)
        } ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        simulatePaste()
        try? await Task.sleep(nanoseconds: 100_000_000)

        pasteboard.clearContents()
        for (typeRaw, data) in savedItems {
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(typeRaw))
        }

        return InjectionResult(success: true, strategy: .clipboard)
    }

    private func simulatePaste() {
        let vKeyCode: CGKeyCode = 0x09
        if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
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
