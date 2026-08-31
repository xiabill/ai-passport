import Combine
import Foundation

public struct BridgeSettings: Equatable, Codable {
    public var devicePrefix: String
    public var outputDevice: String
    public var talkKey: String
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

    public static let `default` = BridgeSettings(
        devicePrefix: "FoloVibe",
        outputDevice: "BlackHole 2ch",
        talkKey: "F19",
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
        Hotkey.named(talkKey, in: Hotkey.talkKeys, fallback: Hotkey.talkKeys[6])
    }
    public var send: Hotkey {
        Hotkey.named(sendKey, in: Hotkey.sendKeys, fallback: Hotkey.sendKeys[0])
    }
    public var cancel: Hotkey {
        Hotkey.named(cancelKey, in: Hotkey.cancelKeys, fallback: Hotkey.cancelKeys[0])
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
