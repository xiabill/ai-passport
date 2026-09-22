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
    /// How the key is delivered. Which one an application wants is not
    /// something this app can detect: some dictation tools start on a double
    /// press, others on a held key.
    public enum Style: String, Codable, CaseIterable, Equatable {
        case tap
        case double
        case hold

        public var title: String {
            switch self {
            case .tap: return "按一下"
            case .double: return "连按两下"
            case .hold: return "按住不放"
            }
        }
    }

    public var style: Style
    /// Volume, play/pause and the like are not ordinary keys; they travel as
    /// system media events and need their own posting path.
    public var isMedia: Bool

    public init(keyCode: UInt16, modifiers: UInt64, label: String,
                style: Style = .tap, isMedia: Bool = false) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
        self.style = style
        self.isMedia = isMedia
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers, label, style, isMedia, taps
    }

    /// Strokes written before styles existed were single or double presses.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try c.decode(UInt16.self, forKey: .keyCode)
        modifiers = try c.decode(UInt64.self, forKey: .modifiers)
        label = try c.decode(String.self, forKey: .label)
        isMedia = try c.decodeIfPresent(Bool.self, forKey: .isMedia) ?? false
        if let s = try c.decodeIfPresent(Style.self, forKey: .style) {
            style = s
        } else {
            style = (try c.decodeIfPresent(Int.self, forKey: .taps) ?? 1) > 1 ? .double : .tap
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keyCode, forKey: .keyCode)
        try c.encode(modifiers, forKey: .modifiers)
        try c.encode(label, forKey: .label)
        try c.encode(style, forKey: .style)
        try c.encode(isMedia, forKey: .isMedia)
    }

    /// True when the shortcut is a modifier key by itself, like Right Option.
    /// Those have to be held and released rather than typed.
    public var isModifierOnly: Bool { Self.modifierKeyCodes.contains(keyCode) }

    /// Virtual key codes of the keys that only ever act as modifiers.
    public static let modifierKeyCodes: Set<UInt16> = [
        0x37, 0x36,  // command, right command
        0x38, 0x3C,  // shift, right shift
        0x3A, 0x3D,  // option, right option
        0x3B, 0x3E,  // control, right control
        0x3F,        // fn
    ]

    /// Label plus how it is sent, for a list where both matter.
    public var display: String {
        switch style {
        case .tap: return label
        case .double: return "\(label) ×2"
        case .hold: return "\(label) 按住"
        }
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
