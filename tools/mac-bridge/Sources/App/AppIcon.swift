import AppKit

enum AppIcon {
    static func image(size: CGFloat = 512) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.04, dy: size * 0.04), xRadius: size * 0.22, yRadius: size * 0.22).fill()

        let glow = NSGradient(
            starting: NSColor(calibratedRed: 0.20, green: 0.55, blue: 1, alpha: 0.9),
            ending: NSColor(calibratedRed: 0.55, green: 0.24, blue: 0.95, alpha: 0.9))
        glow?.draw(in: NSRect(x: size * 0.19, y: size * 0.19, width: size * 0.62, height: size * 0.62), relativeCenterPosition: NSPoint(x: 0.35, y: 0.25))

        if let symbol = NSImage(systemSymbolName: "waveform.and.mic", accessibilityDescription: "FoloVibe") {
            let configured = symbol.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: size * 0.24, weight: .bold)) ?? symbol
            NSColor.white.set()
            configured.draw(
                in: NSRect(x: size * 0.26, y: size * 0.31, width: size * 0.48, height: size * 0.38),
                from: .zero,
                operation: .sourceOver,
                fraction: 1)
        }
        return image
    }
}
