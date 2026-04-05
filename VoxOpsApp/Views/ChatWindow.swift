import AppKit
import SwiftUI

final class ChatWindow: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        self.contentView = contentView
        self.title = "VoxOps Agent Chat"
        self.isFloatingPanel = true
        self.level = .floating
        self.becomesKeyOnlyIfNeeded = true
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces]
        self.isMovableByWindowBackground = false
        self.minSize = NSSize(width: 360, height: 400)
        self.center()
    }
}
