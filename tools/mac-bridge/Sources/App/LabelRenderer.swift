import AppKit
import FoloVibeCore

/// Draws a key label into the 8-bit alpha bitmap the device shows tinted in
/// the key's colour. The Mac has every font; the device only has the few
/// hundred characters its firmware uses, so any text it did not ship with
/// would otherwise render as boxes.
enum LabelRenderer {
    static func render(_ text: String, main: Bool) -> Data {
        let (w, h) = main ? VibeProtocol.labelMain : VibeProtocol.labelAlt
        let weight: NSFont.Weight = main ? .semibold : .medium
        var size: CGFloat = main ? 16 : 14
        var attr = attributed(text, size, weight)
        // Shrink rather than clip: a long name is still better whole.
        while attr.size().width > CGFloat(w) - 1, size > 9 {
            size -= 1
            attr = attributed(text, size, weight)
        }

        // Draw on a roomy scratch canvas, then place the ink itself. Line
        // metrics differ between fonts, so centring the line box would leave
        // CJK and Latin sitting at different heights.
        let sw = w + 32, sh = h * 3
        guard let scratch = gray(sw, sh) else { return Data(count: w * h) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: scratch, flipped: false)
        attr.draw(at: CGPoint(x: 16, y: CGFloat(h)))
        NSGraphicsContext.restoreGraphicsState()

        let src = scratch.data!.assumingMemoryBound(to: UInt8.self)
        var minX = sw, maxX = -1, minY = sh, maxY = -1
        for y in 0..<sh {
            for x in 0..<sw where src[y * sw + x] > 8 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        var out = Data(count: w * h)
        guard maxX >= minX else { return out }
        let inkW = maxX - minX + 1, inkH = maxY - minY + 1
        let dx = main ? (w - inkW) / 2 : w - inkW
        let dy = (h - inkH) / 2
        out.withUnsafeMutableBytes { dst in
            let d = dst.bindMemory(to: UInt8.self)
            for y in 0..<inkH {
                let ty = y + dy
                guard ty >= 0, ty < h else { continue }
                for x in 0..<inkW {
                    let tx = x + dx
                    guard tx >= 0, tx < w else { continue }
                    d[ty * w + tx] = src[(minY + y) * sw + minX + x]
                }
            }
        }
        return out
    }

    private static func attributed(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight)
        -> NSAttributedString
    {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.white,
        ])
    }

    /// Rows run top to bottom in memory, which is the order the device reads.
    private static func gray(_ w: Int, _ h: Int) -> CGContext? {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                            space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)
        ctx?.setFillColor(gray: 0, alpha: 1)
        ctx?.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx
    }
}
