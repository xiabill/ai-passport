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

/// What a gesture should do. These are behaviours, not applications: which
/// app a shortcut happens to drive is the user's business, so a gesture that
/// starts dictation carries the shortcut for whatever they use.
public enum ButtonAction: String, CaseIterable, Codable, Hashable {
    case none
    case voice
    case key
    case clear
    case handoff

    public var title: String {
        switch self {
        case .none: return "无"
        case .voice: return "语音输入"
        case .key: return "发送按键"
        case .clear: return "全选并删除"
        case .handoff: return "交给另一台 Mac"
        }
    }

    /// True for the actions that carry a shortcut of their own.
    public var needsStroke: Bool { self == .voice || self == .key }

    /// Recording has to start on the device itself: waiting for a round trip
    /// would clip the first syllable. The device only needs this one bit.
    public var isRecording: Bool { self == .voice }

    /// The short name the device prints under a key when no label is set.
    public var deviceTitle: String {
        switch self {
        case .none: return "--"
        case .voice: return "语音"
        case .key: return "按键"
        case .clear: return "删除"
        case .handoff: return "切换"
        }
    }

    /// Wire code sent to the device (VIBE_ACT_* in vibe_protocol.h), which
    /// uses it only to arm the microphone and label the keys. Codes for the
    /// actions this app used to have are retired rather than reused, so an
    /// older device never misreads a new binding.
    public var code: UInt8 {
        switch self {
        case .none: return 0
        case .voice: return 1
        case .clear: return 7
        case .key: return 9
        case .handoff: return 10
        }
    }

    /// Bindings written when every shortcut was its own action, or when they
    /// were named after input methods. Anything that sends one key is now the
    /// same action carrying that key; `ButtonMap` fills in the stroke.
    public init(legacy raw: String) {
        switch raw {
        case "typelessDictate", "typelessTranslate", "typelessAsk", "doubao": self = .voice
        case "customKey", "enter", "newline", "selectAll": self = .key
        case "doubaoSelectAll": self = .key
        case "doubaoClear": self = .clear
        default: self = ButtonAction(rawValue: raw) ?? .none
        }
    }

    /// The preset a retired action turns into, so an upgrade keeps doing what
    /// it did rather than silently sending nothing.
    static func legacyPreset(_ raw: String) -> KeyPreset? {
        switch raw {
        case "enter": return KeyPreset.find("return")
        case "newline": return KeyPreset.find("newline")
        case "selectAll", "doubaoSelectAll": return KeyPreset.find("selectAll")
        default: return nil
        }
    }
}

public struct ButtonMap: Codable, Equatable {
    private var bindings: [String: ButtonAction]
    /// The shortcut a gesture sends; needed by voice input and send-key.
    private var strokes: [String: KeyStroke]
    /// What the device screen says for a gesture, when the built-in name will
    /// not do — a different input method behind the same action, say.
    private var labels: [String: String]
    /// What each slot was bound to before actions stopped being named after
    /// input methods. Not stored: it only exists to carry an old setup over.
    public private(set) var legacyBindings: [String: String] = [:]

    public init(bindings: [String: ButtonAction] = [:],
                strokes: [String: KeyStroke] = [:],
                labels: [String: String] = [:]) {
        self.bindings = bindings
        self.strokes = strokes
        self.labels = labels
    }

    private enum CodingKeys: String, CodingKey {
        case bindings, strokes, labels
    }

    /// Configurations written before custom keys existed have no `strokes`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent([String: String].self, forKey: .bindings) ?? [:]
        bindings = raw.mapValues { ButtonAction(legacy: $0) }
        // Retired actions that were simply one key become that key right here:
        // nothing outside this type is needed to know what Return meant. Only
        // the input-method ones wait for adoptLegacyStrokes, whose keys used
        // to live in settings.
        legacyBindings = raw.filter { ButtonAction(rawValue: $0.value) == nil }
        strokes = try c.decodeIfPresent([String: KeyStroke].self, forKey: .strokes) ?? [:]
        labels = try c.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        for (slot, value) in raw {
            guard let preset = ButtonAction.legacyPreset(value) else { continue }
            if strokes[slot] == nil { strokes[slot] = preset.stroke }
            if labels[slot] == nil { labels[slot] = preset.short }
        }
    }

    /// The custom screen label, or nil to use the built-in name.
    public func label(_ key: ButtonKey, _ gesture: ButtonGesture) -> String? {
        let text = labels[Self.slot(key, gesture)]?.trimmingCharacters(in: .whitespaces) ?? ""
        return text.isEmpty ? nil : text
    }

    public mutating func setLabel(_ key: ButtonKey, _ gesture: ButtonGesture, _ text: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespaces) ?? ""
        labels[Self.slot(key, gesture)] = trimmed.isEmpty ? nil : trimmed
    }

    /// Fills in the shortcut for gestures migrated from the old input-method
    /// actions, whose keys used to live in settings rather than per gesture.
    /// Without this a working setup would go silent until every gesture was
    /// recorded again.
    public mutating func adoptLegacyStrokes(dictation: KeyStroke?, doubao: KeyStroke?) {
        for (slot, raw) in legacyBindings where strokes[slot] == nil {
            switch raw {
            case "doubao": strokes[slot] = doubao
            case "typelessDictate": strokes[slot] = dictation
            case "typelessTranslate":
                strokes[slot] = dictation.map { shifted($0, by: KeyStroke.shift, symbol: "⇧") }
            case "typelessAsk":
                strokes[slot] = dictation.map { spaced($0) }
            default: break
            }
        }
        legacyBindings = [:]
    }

    /// The old translation shortcut was the dictation key plus Shift.
    private func shifted(_ s: KeyStroke, by flag: UInt64, symbol: String) -> KeyStroke {
        KeyStroke(keyCode: s.keyCode, modifiers: s.modifiers | flag,
                  label: symbol + s.label, style: s.style)
    }

    /// And "ask anything" was the dictation key followed by Space, which a
    /// single stroke cannot express; the base key is the closest honest thing.
    private func spaced(_ s: KeyStroke) -> KeyStroke { s }

    /// What the device should call a gesture: the user's own label, else the
    /// preset's short name, else the key itself. A key without a name would
    /// otherwise show a generic "custom" that says nothing about what it does.
    public func screenName(_ key: ButtonKey, _ gesture: ButtonGesture) -> String? {
        if let own = label(key, gesture) { return own }
        guard action(key, gesture) == .key, let s = stroke(key, gesture) else { return nil }
        return KeyPreset.matching(s)?.short ?? s.label
    }

    /// Wire slot for a gesture: button * 3 + gesture, as the firmware counts.
    public static func wireSlot(_ key: ButtonKey, _ gesture: ButtonGesture) -> UInt8 {
        UInt8(key.rawValue * 3 + gesture.rawValue)
    }

    public func stroke(_ key: ButtonKey, _ gesture: ButtonGesture) -> KeyStroke? {
        strokes[Self.slot(key, gesture)]
    }

    public mutating func setStroke(_ key: ButtonKey, _ gesture: ButtonGesture,
                                   _ stroke: KeyStroke?) {
        strokes[Self.slot(key, gesture)] = stroke
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

    /// A usable starting point: voice input on the outer keys, confirming and
    /// editing in the middle where the finger rests. Every binding here is one
    /// the user can change, and the presets show how.
    public static let `default`: ButtonMap = {
        var map = ButtonMap()
        map.set(.up, .click, .voice)
        map.bind(.up, .double, preset: "copy")
        map.bind(.up, .long, preset: "paste")
        map.bind(.mid, .click, preset: "return")
        map.bind(.mid, .double, preset: "newline")
        map.set(.mid, .long, .clear)
        map.set(.down, .click, .voice)
        map.bind(.down, .double, preset: "undo")
        map.set(.down, .long, .handoff)
        return map
    }()

    /// Binds a gesture to a ready-made shortcut, naming the key on the device
    /// screen at the same time.
    public mutating func bind(_ key: ButtonKey, _ gesture: ButtonGesture, preset id: String) {
        guard let preset = KeyPreset.find(id) else { return }
        set(key, gesture, .key)
        setStroke(key, gesture, preset.stroke)
        setLabel(key, gesture, preset.short)
    }
}
