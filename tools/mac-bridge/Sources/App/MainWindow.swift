import AppKit
import SwiftUI

enum MainWindow {
    private static var window: NSWindow?
    /// Narrow on purpose: this sits beside whatever the user is typing into.
    /// Every page is laid out for exactly this width.
    static let width: CGFloat = 420

    static func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let root = RootView(model: AppModel.shared)
        let hosting = NSHostingView(rootView: root)
        // SwiftUI otherwise rewrites the window's size limits from the content
        // and the width below never held: the window could be dragged to any
        // size, which is how pages came to be laid out for widths they never
        // get.
        hosting.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "FoloVibe Bridge"
        window.contentView = hosting
        window.center()
        window.isReleasedWhenClosed = false
        // Fixed width: every page is laid out for exactly this, so nothing can
        // reflow into a mess. Only the height follows the window.
        window.contentMinSize = NSSize(width: Self.width, height: 480)
        window.contentMaxSize = NSSize(width: Self.width, height: 4000)
        window.titlebarAppearsTransparent = false
        // Navigation lives in the in-app top tab bar, so the window needs no
        // toolbar of its own.
        window.toolbar = nil
        window.makeKeyAndOrderFront(nil)
        Self.window = window
        DispatchQueue.main.async {
            window.toolbar = nil
        }
    }
}
