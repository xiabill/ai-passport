import Foundation

public enum TypelessState: UInt8, Equatable {
    case idle = 0
    case recording = 1
    case processing = 2
    case down = 3

    public var title: String {
        switch self {
        case .idle: return "空闲"
        case .recording: return "录音中"
        case .processing: return "转写中"
        case .down: return "未运行"
        }
    }

    /// `history_v2` live state: a row is inserted when dictation starts.
    /// status NULL + duration NULL = recording; status NULL + duration set = processing;
    /// status set = terminal idle.
    public static func derive(running: Bool, hasRow: Bool, statusNull: Bool, durationNull: Bool)
        -> TypelessState
    {
        guard running else { return .down }
        guard hasRow else { return .idle }
        if statusNull && durationNull { return .recording }
        if statusNull { return .processing }
        return .idle
    }
}
