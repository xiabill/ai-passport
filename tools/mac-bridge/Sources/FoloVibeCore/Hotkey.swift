import Foundation

/// Carbon virtual key codes stored by name so settings stay readable.
public struct Hotkey: Equatable, Hashable {
    public var name: String
    public var carbon: UInt16

    public init(name: String, carbon: UInt16) {
        self.name = name
        self.carbon = carbon
    }

    public static let talkKeys: [Hotkey] = [
        Hotkey(name: "F13", carbon: 0x69),
        Hotkey(name: "F14", carbon: 0x6B),
        Hotkey(name: "F15", carbon: 0x71),
        Hotkey(name: "F16", carbon: 0x6A),
        Hotkey(name: "F17", carbon: 0x40),
        Hotkey(name: "F18", carbon: 0x4F),
        Hotkey(name: "F19", carbon: 0x50),
        Hotkey(name: "F20", carbon: 0x5A),
    ]

    public static let sendKeys: [Hotkey] = [
        Hotkey(name: "Return", carbon: 0x24),
        Hotkey(name: "Space", carbon: 0x31),
        Hotkey(name: "Tab", carbon: 0x30),
    ]

    public static let cancelKeys: [Hotkey] = [
        Hotkey(name: "Escape", carbon: 0x35),
        Hotkey(name: "Delete", carbon: 0x33),
    ]

    public static func named(_ name: String, in list: [Hotkey], fallback: Hotkey) -> Hotkey {
        list.first { $0.name == name } ?? fallback
    }
}
