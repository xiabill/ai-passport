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
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "FoloVibe Bridge"
        window.contentView = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 900, height: 620)
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.makeKeyAndOrderFront(nil)
        Self.window = window
    }
}
