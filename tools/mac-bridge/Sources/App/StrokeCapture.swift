import AppKit
import FoloVibeCore
import SwiftUI

/// Records any keyboard shortcut, unlike KeyCaptureSheet which only accepts the
/// fixed list of talk/Doubao/send keys.
struct StrokeCaptureSheet: View {
    let title: String
    let onCapture: (KeyStroke) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text(title).font(.headline)
            Text("按下想要绑定的快捷键")
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "keyboard")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity, minHeight: 68)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            StrokeRecorder { stroke in
                onCapture(stroke)
                dismiss()
            }
            .frame(height: 0)
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(22)
        .frame(width: 320)
    }
}

private struct StrokeRecorder: NSViewRepresentable {
    let onCapture: (KeyStroke) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.onCapture = onCapture
        return v
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.onCapture = onCapture
    }
}

final class RecorderView: NSView {
    var onCapture: ((KeyStroke) -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let mods = UInt64(event.modifierFlags.rawValue) & KeyStroke.modifierMask
        // A bare modifier is not a shortcut; wait for a real key.
        let name = Self.keyName(for: event)
        onCapture?(KeyStroke(
            keyCode: event.keyCode,
            modifiers: mods,
            label: KeyStroke.label(keyCode: event.keyCode, modifiers: mods, keyName: name)))
    }

    /// Prefers the unmodified character so ⌘C reads as "C" rather than the
    /// control character the modifier produces.
    private static func keyName(for event: NSEvent) -> String {
        if let special = specialNames[event.keyCode] { return special }
        let raw = event.charactersIgnoringModifiers ?? ""
        return raw.isEmpty ? "键\(event.keyCode)" : raw.uppercased()
    }

    private static let specialNames: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "空格", 51: "⌫", 53: "esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
