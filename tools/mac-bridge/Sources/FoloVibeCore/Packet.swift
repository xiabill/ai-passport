import Foundation

/// Wire format shared with the Passport firmware.
public enum VibeProtocol {
    public static let audioHeader = 6
    public static let audioADPCM = 160
    public static let audioPacket = 166
    public static let flagEOS: UInt8 = 0x01

    /// Raw gesture events: 0x20 | (button << 2) | gesture.
    public static let gestureBase: UInt8 = 0x20
    /// Control write: 0x91 followed by one action code per gesture.
    public static let ctrlActions: UInt8 = 0x91

    /// Read-only firmware version, so the bridge can tell whether the device
    /// needs an upgrade.
    public static let versionUUID = "F0100005-0000-4A6B-9E10-464F4C4F5631"
    /// Firmware image stream: one 6-byte header ('F','W', length LE32) then raw
    /// image bytes.
    public static let otaUUID = "F0100006-0000-4A6B-9E10-464F4C4F5631"

    public static func otaHeader(length: Int) -> Data {
        var d = Data([0x46, 0x57])
        let n = UInt32(length)
        d.append(contentsOf: [
            UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF),
            UInt8((n >> 16) & 0xFF), UInt8((n >> 24) & 0xFF),
        ])
        return d
    }

    public static let serviceUUID = "F0100001-0000-4A6B-9E10-464F4C4F5631"
    public static let audioUUID = "F0100002-0000-4A6B-9E10-464F4C4F5631"
    public static let eventUUID = "F0100003-0000-4A6B-9E10-464F4C4F5631"
    public static let controlUUID = "F0100004-0000-4A6B-9E10-464F4C4F5631"
    public static let powerModeStandard: UInt8 = 0x80
    public static let powerModeEco: UInt8 = 0x81
    public static let powerModeUltra: UInt8 = 0x82
}

public enum VibeEvent: UInt8, CaseIterable, Equatable {
    case start = 1
    case stop = 2
    case enter = 3
    case doubaoStart = 5
    case doubaoStop = 6
    case doubaoStopAndSend = 7
    case typelessTranslate = 8
    case typelessAsk = 9
    case doubaoSelectAll = 10
    case doubaoClear = 11

    public var title: String {
        switch self {
        case .start: return "开始说话"
        case .stop: return "停止说话"
        case .enter: return "发送"
        case .doubaoStart: return "豆包开始"
        case .doubaoStop: return "豆包停止"
        case .doubaoStopAndSend: return "豆包停止并发送"
        case .typelessTranslate: return "Typeless 翻译"
        case .typelessAsk: return "Typeless 随便问"
        case .doubaoSelectAll: return "豆包全选并删除"
        case .doubaoClear: return "豆包清空"
        }
    }
}

public struct AudioPacket: Equatable {
    public var seq: UInt16
    public var predictor: Int16
    public var stepIndex: UInt8
    public var flags: UInt8
    public var eos: Bool
    public var adpcm: Data

    public static func parse(_ data: Data) -> AudioPacket? {
        guard data.count == VibeProtocol.audioPacket || data.count == VibeProtocol.audioHeader
        else { return nil }
        let seq = UInt16(data[0]) | (UInt16(data[1]) << 8)
        let predictor = Int16(bitPattern: UInt16(data[2]) | (UInt16(data[3]) << 8))
        let step = data[4]
        let flags = data[5]
        let eos = data.count == VibeProtocol.audioHeader || (flags & VibeProtocol.flagEOS) != 0
        let adpcm = eos ? Data() : data.subdata(in: 6..<data.count)
        return AudioPacket(
            seq: seq, predictor: predictor, stepIndex: step, flags: flags, eos: eos, adpcm: adpcm)
    }
}

/// A button gesture reported by the device. Replaces the old semantic events:
/// the device says what was pressed, the bridge decides what it means.
public struct GestureEvent: Equatable {
    public var key: ButtonKey
    public var gesture: ButtonGesture

    public init(key: ButtonKey, gesture: ButtonGesture) {
        self.key = key
        self.gesture = gesture
    }

    public static func parse(_ byte: UInt8) -> GestureEvent? {
        guard byte >= VibeProtocol.gestureBase else { return nil }
        let payload = byte - VibeProtocol.gestureBase
        guard let key = ButtonKey(rawValue: Int(payload >> 2)),
            let gesture = ButtonGesture(rawValue: Int(payload & 0x03))
        else { return nil }
        return GestureEvent(key: key, gesture: gesture)
    }

    public var title: String { "\(key.title)\(gesture.title)" }
}
