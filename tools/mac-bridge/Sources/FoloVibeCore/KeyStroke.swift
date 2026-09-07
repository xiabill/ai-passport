import Foundation

/// An arbitrary keyboard shortcut: a virtual key plus its modifiers. Lets a
/// gesture drive anything the Mac can receive, not just the actions this app
/// knows about.
public struct KeyStroke: Codable, Equatable, Hashable {
    public var keyCode: UInt16
    /// Raw CGEventFlags, masked to the four modifiers a user can press.
    public var modifiers: UInt64
    /// What to show in the UI and on the device, e.g. "⌘C".
    public var label: String

    public init(keyCode: UInt16, modifiers: UInt64, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    /// Only these four are worth carrying; the rest of CGEventFlags describes
    /// event state rather than something a person held down.
    public static let command: UInt64 = 1 << 20
    public static let shift: UInt64 = 1 << 17
    public static let option: UInt64 = 1 << 19
    public static let control: UInt64 = 1 << 18
    public static let modifierMask: UInt64 = command | shift | option | control

    /// Builds the conventional symbol order: ⌃⌥⇧⌘ then the key.
    public static func label(keyCode: UInt16, modifiers: UInt64, keyName: String) -> String {
        var s = ""
        if modifiers & control != 0 { s += "⌃" }
        if modifiers & option != 0 { s += "⌥" }
        if modifiers & shift != 0 { s += "⇧" }
        if modifiers & command != 0 { s += "⌘" }
        return s + keyName
    }
}
