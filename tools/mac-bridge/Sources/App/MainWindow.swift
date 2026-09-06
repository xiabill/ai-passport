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
        window.minSize = NSSize(width: 720, height: 520)
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
