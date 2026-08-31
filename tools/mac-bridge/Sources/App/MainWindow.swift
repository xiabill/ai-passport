import AppKit
import SwiftUI

enum MainWindow {
    private static var window: NSWindow?

    static func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let root = RootView(model: AppModel.shared)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "FoloVibe"
        window.contentView = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 480)
        window.makeKeyAndOrderFront(nil)
        Self.window = window
    }
}
