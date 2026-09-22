import AppKit
import FoloVibeCore
import SwiftUI

/// Records whatever key the user presses for a gesture, including a modifier
/// on its own — Right Option and Fn are what several dictation apps listen
/// for, and they never arrive as an ordinary key press.
struct StrokeCaptureSheet: View {
    let title: String
    let onCapture: (KeyStroke) -> Void
    @ObservedObject private var draft: StrokeDraft
    @Environment(\.dismiss) private var dismiss

    init(title: String, current: KeyStroke? = nil, onCapture: @escaping (KeyStroke) -> Void) {
        self.title = title
        self.onCapture = onCapture
        // Opening on an existing binding shows it, so changing only how it is
        // sent does not mean recording the key again.
        self.draft = StrokeDraft(current)
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(title).font(.headline)
            Text(draft.stroke == nil ? "按下想要绑定的按键" : "再按一次可以改")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(draft.stroke?.label ?? "…")
                .font(.system(size: 26, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 68)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            Picker("", selection: $draft.style) {
                ForEach(KeyStroke.Style.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("有的软件要连按两下才唤起，有的要按住不放")
                .font(.caption2)
                .foregroundStyle(.secondary)

            StrokeRecorder { draft.stroke = $0 }
                .frame(height: 0)

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    if var s = draft.stroke {
                        s.style = draft.style
                        onCapture(s)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.stroke == nil)
            }
        }
        .padding(22)
        .frame(width: 340)
    }
}

/// Holds what has been pressed so far. A plain @State would be reset by the
/// recorder view rebuilding on every keystroke.
private final class StrokeDraft: ObservableObject {
    @Published var stroke: KeyStroke?
    @Published var style: KeyStroke.Style

    init(_ current: KeyStroke?) {
        stroke = current
        style = current?.style ?? .tap
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
        let name = Self.keyName(for: event)
        onCapture?(KeyStroke(
            keyCode: event.keyCode,
            modifiers: mods,
            label: KeyStroke.label(keyCode: event.keyCode, modifiers: mods, keyName: name)))
    }

    /// Pressing a modifier alone arrives here, not in keyDown. Recorded on the
    /// release so holding one down does not fire repeatedly.
    override func flagsChanged(with event: NSEvent) {
        guard KeyStroke.modifierKeyCodes.contains(event.keyCode) else { return }
        let stillDown = UInt64(event.modifierFlags.rawValue) & Self.flagMask(event.keyCode) != 0
        guard !stillDown else { return }
        let name = Self.modifierNames[event.keyCode] ?? "修饰键"
        onCapture?(KeyStroke(keyCode: event.keyCode, modifiers: 0, label: name))
    }

    private static func flagMask(_ keyCode: UInt16) -> UInt64 {
        switch keyCode {
        case 0x37, 0x36: return UInt64(NSEvent.ModifierFlags.command.rawValue)
        case 0x38, 0x3C: return UInt64(NSEvent.ModifierFlags.shift.rawValue)
        case 0x3A, 0x3D: return UInt64(NSEvent.ModifierFlags.option.rawValue)
        case 0x3B, 0x3E: return UInt64(NSEvent.ModifierFlags.control.rawValue)
        case 0x3F: return UInt64(NSEvent.ModifierFlags.function.rawValue)
        default: return 0
        }
    }

    private static let modifierNames: [UInt16: String] = [
        0x37: "⌘ 左", 0x36: "⌘ 右",
        0x38: "⇧ 左", 0x3C: "⇧ 右",
        0x3A: "⌥ 左", 0x3D: "⌥ 右",
        0x3B: "⌃ 左", 0x3E: "⌃ 右",
        0x3F: "Fn",
    ]

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
        0x69: "F13", 0x6B: "F14", 0x71: "F15", 0x6A: "F16", 0x40: "F17",
        0x4F: "F18", 0x50: "F19",
    ]
}
