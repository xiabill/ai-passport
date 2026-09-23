import Combine
import Foundation

public enum BridgePowerMode: String, Codable, CaseIterable {
    case standard
    case eco
    case ultra

    public var title: String {
        switch self {
        case .standard: return "标准模式"
        case .eco: return "省电模式"
        case .ultra: return "超级省电"
        }
    }

    public var subtitle: String {
        switch self {
        case .standard: return "保持蓝牙易连接，15 分钟后深度睡眠"
        case .eco: return "闲置后暂停广播，5 分钟后深度睡眠"
        case .ultra: return "30 秒熄屏，2 分钟后深度睡眠，适合放着不用"
        }
    }

    public var symbol: String {
        switch self {
        case .standard: return "bolt.fill"
        case .eco: return "leaf.fill"
        case .ultra: return "moon.zzz.fill"
        }
    }
}

public struct BridgeSettings: Equatable, Codable {
    public var devicePrefix: String
    public var outputDevice: String
    public var buttons: ButtonMap
    public var launchAtLogin: Bool
    public var startHidden: Bool
    public var autoReconnect: Bool
    public var powerMode: BridgePowerMode
    /// How loud the device's cues are, 0 (silent) to 4. Lives on the device
    /// too, so it holds before any Mac connects.
    public var cueVolume: Int

    public init(
        devicePrefix: String,
        outputDevice: String,
        buttons: ButtonMap = .default,
        launchAtLogin: Bool = false,
        startHidden: Bool = false,
        autoReconnect: Bool = true,
        powerMode: BridgePowerMode = .standard,
        cueVolume: Int = 2
    ) {
        self.devicePrefix = devicePrefix
        self.outputDevice = outputDevice
        self.buttons = buttons
        self.launchAtLogin = launchAtLogin
        self.startHidden = startHidden
        self.autoReconnect = autoReconnect
        self.powerMode = powerMode
        self.cueVolume = cueVolume
    }

    public static let `default` = BridgeSettings(
        devicePrefix: "FoloVibe",
        outputDevice: "BlackHole 2ch"
    )

    private enum CodingKeys: String, CodingKey {
        case devicePrefix, outputDevice, buttons
        case launchAtLogin, startHidden, autoReconnect, powerMode, cueVolume
        // Retired: the app no longer knows about particular input methods, so
        // their keys live on the gestures that send them. Decoded once, to
        // carry an existing setup across, then never written again.
        case talkKey, doubaoKey, talkTap, doubaoTap
    }

    /// Settings written by an older version still open, and the shortcuts that
    /// used to be global move onto the gestures that were using them.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BridgeSettings.default
        devicePrefix = try c.decodeIfPresent(String.self, forKey: .devicePrefix) ?? d.devicePrefix
        outputDevice = try c.decodeIfPresent(String.self, forKey: .outputDevice) ?? d.outputDevice
        buttons = try c.decodeIfPresent(ButtonMap.self, forKey: .buttons) ?? d.buttons
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        startHidden = try c.decodeIfPresent(Bool.self, forKey: .startHidden) ?? d.startHidden
        autoReconnect = try c.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? d.autoReconnect
        powerMode = try c.decodeIfPresent(BridgePowerMode.self, forKey: .powerMode) ?? d.powerMode
        cueVolume = try c.decodeIfPresent(Int.self, forKey: .cueVolume) ?? d.cueVolume

        let talk = try c.decodeIfPresent(String.self, forKey: .talkKey)
        let doubao = try c.decodeIfPresent(String.self, forKey: .doubaoKey)
        let doubaoTaps = (try c.decodeIfPresent(String.self, forKey: .doubaoTap)) == "single" ? 1 : 2
        let talkTaps = (try c.decodeIfPresent(String.self, forKey: .talkTap)) == "double" ? 2 : 1
        buttons.adoptLegacyStrokes(
            dictation: Self.legacyStroke(talk, taps: talkTaps),
            doubao: Self.legacyStroke(doubao, taps: doubaoTaps))
    }

    /// Only the keys still in use are written back; the retired ones exist
    /// for reading an old file and are dropped on the next save.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(devicePrefix, forKey: .devicePrefix)
        try c.encode(outputDevice, forKey: .outputDevice)
        try c.encode(buttons, forKey: .buttons)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(startHidden, forKey: .startHidden)
        try c.encode(autoReconnect, forKey: .autoReconnect)
        try c.encode(powerMode, forKey: .powerMode)
        try c.encode(cueVolume, forKey: .cueVolume)
    }

    /// The keys the old settings could name, by the label they were stored as.
    private static func legacyStroke(_ name: String?, taps: Int) -> KeyStroke? {
        guard let name, let code = legacyKeyCodes[name] else { return nil }
        return KeyStroke(keyCode: code, modifiers: 0, label: name,
                         style: taps > 1 ? .double : .tap)
    }

    private static let legacyKeyCodes: [String: UInt16] = [
        "Fn": 0x3F, "Right Option": 0x3D, "Left Option": 0x3A,
        "F13": 0x69, "F14": 0x6B, "F15": 0x71, "F16": 0x6A,
        "F17": 0x40, "F18": 0x4F, "F19": 0x50, "Return": 0x24,
    ]
}

public final class SettingsStore: ObservableObject {
    public static let defaultsKey = "bridgeSettings"
    @Published public var current: BridgeSettings {
        didSet { save() }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
            let decoded = try? JSONDecoder().decode(BridgeSettings.self, from: data)
        {
            current = decoded
        } else {
            current = .default
        }
    }

    public func reset() {
        current = .default
    }

    private func save() {
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
