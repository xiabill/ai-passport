import AVFoundation
import Foundation

/// Arms on the next BLE stream, writes WAV, plays on the default speaker.
final class MicTest {
    private static let sampleRate = 16000
    private static let maxSamples = sampleRate * 20
    private let lock = NSLock()
    private var armed = false
    private var samples = [Int16]()
    private var playback: (AVAudioEngine, AVAudioPlayerNode)?
    private(set) var result: String = "未测试"

    var isArmed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return armed
    }

    func arm() {
        lock.lock()
        armed = true
        samples.removeAll()
        result = "待录：在设备上按确定说话再按确定停止"
        lock.unlock()
        Log.debug("麦克风测试：待录")
    }

    func cancel() {
        lock.lock()
        armed = false
        samples.removeAll()
        result = "已取消"
        lock.unlock()
    }

    func append(_ pcm: [Int16]) {
        lock.lock()
        defer { lock.unlock() }
        guard armed, samples.count < Self.maxSamples else { return }
        samples.append(contentsOf: pcm)
    }

    func finish() {
        lock.lock()
        guard armed, !samples.isEmpty else {
            lock.unlock()
            return
        }
        let pcm = samples
        samples.removeAll()
        armed = false
        lock.unlock()
        let seconds = Double(pcm.count) / Double(Self.sampleRate)
        do {
            let url = try Self.writeWAV(pcm)
            result = String(format: "上次 %.1fs · 峰值 %d · %@", seconds, peak(pcm), url.lastPathComponent)
            Log.debug("麦克风测试已保存 \(url.path)")
            play(url)
        } catch {
            result = "保存失败：\(error.localizedDescription)"
            Log.debug(result)
        }
    }

    private func peak(_ pcm: [Int16]) -> Int {
        pcm.map { $0 == Int16.min ? 32767 : abs(Int($0)) }.max() ?? 0
    }

    private func play(_ url: URL) {
        do {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let file = try AVAudioFile(forReading: url)
            engine.attach(player)
            engine.connect(player, to: engine.outputNode, format: file.processingFormat)
            try engine.start()
            player.scheduleFile(file, at: nil)
            player.play()
            playback = (engine, player)
        } catch {
            Log.debug("回放失败：\(error.localizedDescription)")
        }
    }

    private static func writeWAV(_ pcm: [Int16]) throws -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FoloVibe")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("mic-test.wav")
        let samples = pcm
        let dataSize = UInt32(samples.count * 2)
        var header = Data()
        func ascii(_ s: String) { header.append(contentsOf: s.utf8) }
        func le32(_ v: UInt32) {
            var x = v.littleEndian
            header.append(Data(bytes: &x, count: 4))
        }
        func le16(_ v: UInt16) {
            var x = v.littleEndian
            header.append(Data(bytes: &x, count: 2))
        }
        ascii("RIFF")
        le32(36 + dataSize)
        ascii("WAVE")
        ascii("fmt ")
        le32(16)
        le16(1)
        le16(1)
        le32(UInt32(sampleRate))
        le32(UInt32(sampleRate * 2))
        le16(2)
        le16(16)
        ascii("data")
        le32(dataSize)
        let pcmData = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        try (header + pcmData).write(to: url)
        return url
    }
}
