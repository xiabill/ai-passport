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
    public var talkKey: String
    public var doubaoKey: String
    public var sendKey: String
    public var buttons: ButtonMap
    public var retapEnabled: Bool
    public var retapFromSec: Double
    public var retapToSec: Double
    public var retapMax: Int
    public var typelessPollSec: Double
    public var launchAtLogin: Bool
    public var startHidden: Bool
    public var autoReconnect: Bool
    public var powerMode: BridgePowerMode

    public init(
        devicePrefix: String,
        outputDevice: String,
        talkKey: String,
        doubaoKey: String,
        sendKey: String,
        buttons: ButtonMap = .default,
        retapEnabled: Bool,
        retapFromSec: Double,
        retapToSec: Double,
        retapMax: Int,
        typelessPollSec: Double,
        launchAtLogin: Bool,
        startHidden: Bool,
        autoReconnect: Bool,
        powerMode: BridgePowerMode = .standard
    ) {
        self.devicePrefix = devicePrefix
        self.outputDevice = outputDevice
        self.talkKey = talkKey
        self.doubaoKey = doubaoKey
        self.sendKey = sendKey
        self.buttons = buttons
        self.retapEnabled = retapEnabled
        self.retapFromSec = retapFromSec
        self.retapToSec = retapToSec
        self.retapMax = retapMax
        self.typelessPollSec = typelessPollSec
        self.launchAtLogin = launchAtLogin
        self.startHidden = startHidden
        self.autoReconnect = autoReconnect
        self.powerMode = powerMode
    }

    public static let `default` = BridgeSettings(
        devicePrefix: "FoloVibe",
        outputDevice: "BlackHole 2ch",
        talkKey: "Fn",
        doubaoKey: "Right Option",
        sendKey: "Return",
        buttons: .default,
        retapEnabled: true,
        retapFromSec: 2,
        retapToSec: 6,
        retapMax: 3,
        typelessPollSec: 2,
        launchAtLogin: false,
        startHidden: false,
        autoReconnect: true,
        powerMode: .standard
    )

    public var talk: Hotkey {
        Hotkey.named(talkKey, in: Hotkey.talkKeys, fallback: Hotkey.talkKeys[0])
    }
    public var send: Hotkey {
        Hotkey.named(sendKey, in: Hotkey.sendKeys, fallback: Hotkey.sendKeys[0])
    }
    public var doubao: Hotkey {
        Hotkey.named(doubaoKey, in: Hotkey.doubaoKeys, fallback: Hotkey.doubaoKeys[0])
    }

    private enum CodingKeys: String, CodingKey {
        case devicePrefix, outputDevice, talkKey, doubaoKey, sendKey, buttons
        case retapEnabled, retapFromSec, retapToSec, retapMax, typelessPollSec
        case launchAtLogin, startHidden, autoReconnect, powerMode
    }

    /// Keep existing installations valid when the Doubao setting is added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BridgeSettings.default
        devicePrefix = try c.decodeIfPresent(String.self, forKey: .devicePrefix) ?? d.devicePrefix
        outputDevice = try c.decodeIfPresent(String.self, forKey: .outputDevice) ?? d.outputDevice
        talkKey = try c.decodeIfPresent(String.self, forKey: .talkKey) ?? d.talkKey
        doubaoKey = try c.decodeIfPresent(String.self, forKey: .doubaoKey) ?? d.doubaoKey
        sendKey = try c.decodeIfPresent(String.self, forKey: .sendKey) ?? d.sendKey
        buttons = try c.decodeIfPresent(ButtonMap.self, forKey: .buttons) ?? d.buttons
        retapEnabled = try c.decodeIfPresent(Bool.self, forKey: .retapEnabled) ?? d.retapEnabled
        retapFromSec = try c.decodeIfPresent(Double.self, forKey: .retapFromSec) ?? d.retapFromSec
        retapToSec = try c.decodeIfPresent(Double.self, forKey: .retapToSec) ?? d.retapToSec
        retapMax = try c.decodeIfPresent(Int.self, forKey: .retapMax) ?? d.retapMax
        typelessPollSec = try c.decodeIfPresent(Double.self, forKey: .typelessPollSec) ?? d.typelessPollSec
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        startHidden = try c.decodeIfPresent(Bool.self, forKey: .startHidden) ?? d.startHidden
        autoReconnect = try c.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? d.autoReconnect
        powerMode = try c.decodeIfPresent(BridgePowerMode.self, forKey: .powerMode) ?? d.powerMode
    }
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
