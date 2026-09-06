import Foundation

/// Physical buttons on the Passport, in the order the firmware reports them.
public enum ButtonKey: Int, CaseIterable, Codable, Hashable {
    case up = 0
    case mid = 1
    case down = 2

    public var title: String {
        switch self {
        case .up: return "上键"
        case .mid: return "中键"
        case .down: return "下键"
        }
    }
}

public enum ButtonGesture: Int, CaseIterable, Codable, Hashable {
    case click = 0
    case double = 1
    case long = 2

    public var title: String {
        switch self {
        case .click: return "单击"
        case .double: return "双击"
        case .long: return "长按"
        }
    }
}

/// What a gesture should do. The firmware no longer decides this; it only
/// reports the gesture and lets the bridge map it, so changing a binding never
/// requires reflashing.
public enum ButtonAction: String, CaseIterable, Codable, Hashable {
    case none
    case typelessDictate
    case typelessTranslate
    case typelessAsk
    case doubao
    case enter
    case doubaoSelectAll
    case doubaoClear

    public var title: String {
        switch self {
        case .none: return "无"
        case .typelessDictate: return "Typeless 语音输入"
        case .typelessTranslate: return "Typeless 翻译"
        case .typelessAsk: return "Typeless 随便问"
        case .doubao: return "豆包语音输入"
        case .enter: return "发送回车"
        case .doubaoSelectAll: return "全选"
        case .doubaoClear: return "全选并删除"
        }
    }

    /// Recording actions must start audio capture on the device itself: waiting
    /// for a BLE round trip would clip the first syllable. The device only
    /// needs this one bit, not the action's meaning.
    public var isRecording: Bool {
        switch self {
        case .typelessDictate, .typelessTranslate, .typelessAsk, .doubao: return true
        case .none, .enter, .doubaoSelectAll, .doubaoClear: return false
        }
    }

    /// Wire code sent to the device (VIBE_ACT_* in vibe_protocol.h). The device
    /// uses it only to arm the microphone and label the on-screen key hints.
    public var code: UInt8 {
        switch self {
        case .none: return 0
        case .typelessDictate: return 1
        case .typelessTranslate: return 2
        case .typelessAsk: return 3
        case .doubao: return 4
        case .enter: return 5
        case .doubaoSelectAll: return 6
        case .doubaoClear: return 7
        }
    }

    public var isTypeless: Bool {
        switch self {
        case .typelessDictate, .typelessTranslate, .typelessAsk: return true
        default: return false
        }
    }
}

public struct ButtonMap: Codable, Equatable {
    private var bindings: [String: ButtonAction]

    public init(bindings: [String: ButtonAction] = [:]) {
        self.bindings = bindings
    }

    private static func slot(_ key: ButtonKey, _ gesture: ButtonGesture) -> String {
        "\(key.rawValue).\(gesture.rawValue)"
    }

    public func action(_ key: ButtonKey, _ gesture: ButtonGesture) -> ButtonAction {
        bindings[Self.slot(key, gesture)] ?? .none
    }

    public mutating func set(_ key: ButtonKey, _ gesture: ButtonGesture, _ action: ButtonAction) {
        bindings[Self.slot(key, gesture)] = action
    }

    /// Action codes in gesture-index order (key * 3 + gesture), ready to append
    /// to a VIBE_CTRL_ACTIONS control write.
    public var actionCodes: [UInt8] {
        var out = [UInt8]()
        for key in ButtonKey.allCases {
            for gesture in ButtonGesture.allCases {
                out.append(action(key, gesture).code)
            }
        }
        return out
    }

    /// Mirrors what the firmware used to hardcode, so an existing user keeps
    /// the same behaviour after upgrading.
    public static let `default`: ButtonMap = {
        var map = ButtonMap()
        map.set(.mid, .click, .typelessDictate)
        map.set(.mid, .double, .typelessTranslate)
        map.set(.mid, .long, .typelessAsk)
        map.set(.up, .click, .doubao)
        map.set(.up, .double, .doubaoSelectAll)
        map.set(.up, .long, .doubaoClear)
        map.set(.down, .click, .enter)
        return map
    }()
}
