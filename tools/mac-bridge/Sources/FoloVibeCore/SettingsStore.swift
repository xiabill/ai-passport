import Combine
import Foundation

public struct BridgeSettings: Equatable, Codable {
    public var devicePrefix: String
    public var outputDevice: String
    public var talkKey: String
    public var doubaoKey: String
    public var sendKey: String
    public var cancelKey: String
    public var retapEnabled: Bool
    public var retapFromSec: Double
    public var retapToSec: Double
    public var retapMax: Int
    public var typelessPollSec: Double
    public var launchAtLogin: Bool
    public var startHidden: Bool
    public var autoReconnect: Bool

    public init(
        devicePrefix: String,
        outputDevice: String,
        talkKey: String,
        doubaoKey: String,
        sendKey: String,
        cancelKey: String,
        retapEnabled: Bool,
        retapFromSec: Double,
        retapToSec: Double,
        retapMax: Int,
        typelessPollSec: Double,
        launchAtLogin: Bool,
        startHidden: Bool,
        autoReconnect: Bool
    ) {
        self.devicePrefix = devicePrefix
        self.outputDevice = outputDevice
        self.talkKey = talkKey
        self.doubaoKey = doubaoKey
        self.sendKey = sendKey
        self.cancelKey = cancelKey
        self.retapEnabled = retapEnabled
        self.retapFromSec = retapFromSec
        self.retapToSec = retapToSec
        self.retapMax = retapMax
        self.typelessPollSec = typelessPollSec
        self.launchAtLogin = launchAtLogin
        self.startHidden = startHidden
        self.autoReconnect = autoReconnect
    }

    public static let `default` = BridgeSettings(
        devicePrefix: "FoloVibe",
        outputDevice: "BlackHole 2ch",
        talkKey: "Fn",
        doubaoKey: "Right Option",
        sendKey: "Return",
        cancelKey: "Escape",
        retapEnabled: true,
        retapFromSec: 2,
        retapToSec: 6,
        retapMax: 3,
        typelessPollSec: 2,
        launchAtLogin: false,
        startHidden: false,
        autoReconnect: true
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
    public var cancel: Hotkey {
        Hotkey.named(cancelKey, in: Hotkey.cancelKeys, fallback: Hotkey.cancelKeys[0])
    }

    private enum CodingKeys: String, CodingKey {
        case devicePrefix, outputDevice, talkKey, doubaoKey, sendKey, cancelKey
        case retapEnabled, retapFromSec, retapToSec, retapMax, typelessPollSec
        case launchAtLogin, startHidden, autoReconnect
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
        cancelKey = try c.decodeIfPresent(String.self, forKey: .cancelKey) ?? d.cancelKey
        retapEnabled = try c.decodeIfPresent(Bool.self, forKey: .retapEnabled) ?? d.retapEnabled
        retapFromSec = try c.decodeIfPresent(Double.self, forKey: .retapFromSec) ?? d.retapFromSec
        retapToSec = try c.decodeIfPresent(Double.self, forKey: .retapToSec) ?? d.retapToSec
        retapMax = try c.decodeIfPresent(Int.self, forKey: .retapMax) ?? d.retapMax
        typelessPollSec = try c.decodeIfPresent(Double.self, forKey: .typelessPollSec) ?? d.typelessPollSec
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        startHidden = try c.decodeIfPresent(Bool.self, forKey: .startHidden) ?? d.startHidden
        autoReconnect = try c.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? d.autoReconnect
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
