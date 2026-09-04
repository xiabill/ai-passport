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
        window.minSize = NSSize(width: 980, height: 660)
        window.titlebarAppearsTransparent = false
        // This window has its own in-app navigation. Leaving the automatic
        // split-view toolbar enabled adds a large, redundant sidebar button
        // to the title bar and makes the content feel disconnected.
        window.toolbar = nil
        window.makeKeyAndOrderFront(nil)
        Self.window = window
        // NavigationSplitView can install its automatic sidebar toolbar item
        // after the window is shown. Remove that late-added item as well.
        DispatchQueue.main.async {
            window.toolbar = nil
        }
    }
}
