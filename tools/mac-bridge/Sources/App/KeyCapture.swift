import AppKit
import FoloVibeCore
import SwiftUI

struct KeyCaptureSheet: View {
    let title: String
    let keys: [Hotkey]
    let onCapture: (Hotkey) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            Text("设置\(title)").font(.title3.weight(.semibold))
            Text("请按下要使用的单键，例如 Fn、F19、右 Option 或 Return。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("等待按键…")
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            KeyCaptureRepresentable(keys: keys) { key in
                onCapture(key)
                dismiss()
            }
            .frame(width: 2, height: 2)
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .frame(width: 380)
    }
}

private struct KeyCaptureRepresentable: NSViewRepresentable {
    let keys: [Hotkey]
    let onCapture: (Hotkey) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView(keys: keys, onCapture: onCapture)
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("按键捕获")
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.keys = keys
        nsView.onCapture = onCapture
    }
}

private final class CaptureView: NSView {
    var keys: [Hotkey]
    var onCapture: (Hotkey) -> Void

    init(keys: [Hotkey], onCapture: @escaping (Hotkey) -> Void) {
        self.keys = keys
        self.onCapture = onCapture
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard let key = key(for: event.keyCode) else { return NSSound.beep() }
        onCapture(key)
    }

    override func flagsChanged(with event: NSEvent) {
        let isPressed: Bool
        switch event.keyCode {
        case 58, 61: isPressed = event.modifierFlags.contains(.option)
        case 63: isPressed = event.modifierFlags.contains(.function)
        default: return
        }
        guard isPressed, let key = key(for: event.keyCode) else { return }
        onCapture(key)
    }

    private func key(for keyCode: UInt16) -> Hotkey? {
        let carbon: UInt16
        switch keyCode {
        case 36: carbon = 0x24
        case 48: carbon = 0x30
        case 49: carbon = 0x31
        case 51: carbon = 0x33
        case 53: carbon = 0x35
        case 58: carbon = 0x3A
        case 61: carbon = 0x3D
        case 63: carbon = 0x3F
        case 64: carbon = 0x40
        case 69: carbon = 0x45
        case 105: carbon = 0x69
        case 106: carbon = 0x6A
        case 107: carbon = 0x6B
        case 113: carbon = 0x71
        case 79: carbon = 0x4F
        case 80: carbon = 0x50
        case 90: carbon = 0x5A
        default: return nil
        }
        return keys.first { $0.carbon == carbon }
    }
}
