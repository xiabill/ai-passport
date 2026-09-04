import AppKit

enum AppIcon {
    static func image(size: CGFloat = 512) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let iconRect = rect.insetBy(dx: size * 0.04, dy: size * 0.04)
        let iconPath = NSBezierPath(
            roundedRect: iconRect,
            xRadius: size * 0.22,
            yRadius: size * 0.22)
        NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.14, alpha: 1).setFill()
        iconPath.fill()

        let glow = NSGradient(
            starting: NSColor(calibratedRed: 0.10, green: 0.45, blue: 0.98, alpha: 0.95),
            ending: NSColor(calibratedRed: 0.42, green: 0.16, blue: 0.88, alpha: 0.95))
        let innerRect = iconRect.insetBy(dx: size * 0.08, dy: size * 0.08)
        NSGraphicsContext.saveGraphicsState()
        iconPath.addClip()
        glow?.draw(in: innerRect, relativeCenterPosition: NSPoint(x: 0.28, y: 0.22))
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.18).setStroke()
        iconPath.lineWidth = size * 0.012
        iconPath.stroke()

        let ring = NSBezierPath(ovalIn: NSRect(x: size * 0.19, y: size * 0.19, width: size * 0.62, height: size * 0.62))
        NSColor.white.withAlphaComponent(0.10).setStroke()
        ring.lineWidth = size * 0.018
        ring.stroke()

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
