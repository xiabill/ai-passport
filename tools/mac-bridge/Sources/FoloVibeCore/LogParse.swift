import Foundation

public struct LogLine: Equatable, Identifiable {
    public var id: Int
    public var time: String
    public var category: String
    public var message: String

    public init(id: Int = 0, time: String, category: String, message: String) {
        self.id = id
        self.time = time
        self.category = category
        self.message = message
    }

    /// "HH:mm:ss.SSS [分类] 内容"
    public static func parse(_ line: String) -> LogLine {
        guard let open = line.firstIndex(of: "["), let close = line.firstIndex(of: "]"),
            open < close, line.distance(from: line.startIndex, to: open) <= 14
        else {
            return LogLine(time: "", category: "", message: line)
        }
        return LogLine(
            time: String(line[line.startIndex..<open]).trimmingCharacters(in: .whitespaces),
            category: String(line[line.index(after: open)..<close]),
            message: String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces))
    }
}

public enum LogCategory {
    public static let all = ["系统", "蓝牙", "音频", "按键", "Typeless", "调试"]
}
