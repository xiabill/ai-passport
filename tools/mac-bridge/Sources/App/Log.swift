import AppKit
import Combine
import FoloVibeCore
import Foundation

enum Log {
    static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("folovibe-bridge.log")
    }()

    private static let lock = NSLock()
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    private static let maxBytes: UInt64 = 5 * 1024 * 1024

    static func sys(_ m: String) { write("系统", m) }
    static func ble(_ m: String) { write("蓝牙", m) }
    static func audio(_ m: String) { write("音频", m) }
    static func key(_ m: String) { write("按键", m) }
    static func typeless(_ m: String) { write("Typeless", m) }
    static func debug(_ m: String) { write("调试", m) }

    static func write(_ category: String, _ message: String) {
        let time = stamp.string(from: Date())
        LogStore.shared.append(time: time, category: category, message: message)
        let line = "\(time) [\(category)] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        lock.lock()
        defer { lock.unlock() }
        rotateIfNeeded()
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func rotateIfNeeded() {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        guard size > maxBytes else { return }
        let old = url.appendingPathExtension("old")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: url, to: old)
    }
}

final class LogStore: ObservableObject {
    static let shared = LogStore()
    private static let limit = 4000
    @Published private(set) var lines: [LogLine] = []
    private var nextID = 0

    private init() {
        if let text = try? String(contentsOf: Log.url, encoding: .utf8) {
            let tail = text.split(separator: "\n", omittingEmptySubsequences: true).suffix(400)
            for raw in tail {
                add(LogLine.parse(String(raw)))
            }
        }
    }

    func append(time: String, category: String, message: String) {
        DispatchQueue.main.async { [self] in
            add(LogLine(time: time, category: category, message: message))
        }
    }

    func clear() { lines.removeAll() }

    private func add(_ line: LogLine) {
        lines.append(
            LogLine(id: nextID, time: line.time, category: line.category, message: line.message))
        nextID += 1
        if lines.count > Self.limit { lines.removeFirst(lines.count - Self.limit) }
    }
}

final class LogFilter: ObservableObject {
    @Published var hidden = Set<String>()
    @Published var search = ""
    @Published var autoScroll = true
}
