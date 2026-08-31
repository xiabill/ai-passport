import Foundation

/// Wire format shared with the Passport firmware.
public enum VibeProtocol {
    public static let audioHeader = 6
    public static let audioADPCM = 160
    public static let audioPacket = 166
    public static let flagEOS: UInt8 = 0x01

    public static let serviceUUID = "F0100001-0000-4A6B-9E10-464F4C4F5631"
    public static let audioUUID = "F0100002-0000-4A6B-9E10-464F4C4F5631"
    public static let eventUUID = "F0100003-0000-4A6B-9E10-464F4C4F5631"
    public static let controlUUID = "F0100004-0000-4A6B-9E10-464F4C4F5631"
}

public enum VibeEvent: UInt8, CaseIterable, Equatable {
    case start = 1
    case stop = 2
    case enter = 3
    case cancel = 4

    public var title: String {
        switch self {
        case .start: return "开始说话"
        case .stop: return "停止说话"
        case .enter: return "发送"
        case .cancel: return "取消"
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
