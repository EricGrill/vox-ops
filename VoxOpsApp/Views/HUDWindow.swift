import AppKit
import SwiftUI

final class HUDWindow: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 48, height: 48),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false
        )
        self.contentView = contentView
        self.isFloatingPanel = true
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.maxX - 64, y: f.minY + 16))
        }
    }
}
