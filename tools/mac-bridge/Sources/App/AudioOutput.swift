import AVFoundation
import CoreAudio
import Foundation

final class AudioOutput {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private let lock = NSLock()
    private var fifo = [Float]()
    private var primed = false
    private let primeFrames = 1280
    private let maxFrames = 8000
    private var sourceNode: AVAudioSourceNode!
    private var deviceName = "BlackHole 2ch"
    private var testTone = false
    private var phase: Double = 0
    private(set) var renderCalls = 0
    private var pushes = 0
    private var lastPeak: Int = 0

    var peak: Int {
        lock.lock()
        defer { lock.unlock() }
        return lastPeak
    }

    var isRunning: Bool { engine.isRunning }

    init() {
        sourceNode = AVAudioSourceNode(format: format) {
            [weak self] isSilence, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let out = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let n = Int(frameCount)
            self.lock.lock()
            self.renderCalls += 1
            if self.testTone {
                self.lock.unlock()
                isSilence.pointee = ObjCBool(false)
                let inc = 2.0 * Double.pi * 440.0 / 16000.0
                var p = self.phase
                for i in 0..<n {
                    out[i] = Float(sin(p) * 0.2)
                    p += inc
                    if p > 2 * .pi { p -= 2 * .pi }
                }
                self.phase = p
                return noErr
            }
            if !self.primed && self.fifo.count >= self.primeFrames { self.primed = true }
            let avail = self.primed ? min(n, self.fifo.count) : 0
            for i in 0..<avail { out[i] = self.fifo[i] }
            if avail > 0 { self.fifo.removeFirst(avail) }
            if avail < n { self.primed = false }
            self.lock.unlock()
            for i in avail..<n { out[i] = 0 }
            isSilence.pointee = ObjCBool(avail == 0)
            return noErr
        }
    }

    func start(deviceNameContains name: String) throws {
        deviceName = name
        if sourceNode.engine == nil { engine.attach(sourceNode) }
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.rebuild(reason: "配置变更")
        }
        try connectAndStart()
        Log.audio("输出设备 \(name)")
    }

    private func connectAndStart() throws {
        guard let deviceID = Self.findOutputDevice(nameContains: deviceName) else {
            throw NSError(
                domain: "FoloVibe", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "找不到输出设备 \(deviceName)"]
            )
        }
        try engine.outputNode.auAudioUnit.setDeviceID(deviceID)
        engine.connect(sourceNode, to: engine.outputNode, format: format)
        if !engine.isRunning { try engine.start() }
    }

    func rebuild(reason: String) {
        Log.audio("重建引擎（\(reason)）")
        engine.stop()
        engine.reset()
        do {
            try connectAndStart()
            lock.lock()
            primed = false
            lock.unlock()
            Log.audio("引擎已重建")
        } catch {
            Log.audio("重建失败：\(error.localizedDescription)")
        }
    }

    func playTestTone(seconds: Double = 2) {
        Log.debug("播放 \(Int(seconds)) 秒 440Hz 测试音")
        testTone = true
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.testTone = false
        }
    }

    func push(_ samples: [Int16]) {
        lock.lock()
        pushes += 1
        lastPeak = 0
        for s in samples {
            let v = s == Int16.min ? 32767 : abs(Int(s))
            if v > lastPeak { lastPeak = v }
            fifo.append(Float(s) / 32768.0)
        }
        if fifo.count > maxFrames { fifo.removeFirst(fifo.count - maxFrames) }
        lock.unlock()
    }

    static func findOutputDevice(nameContains needle: String) -> AudioDeviceID? {
        let devices = outputDevices()
        for dev in devices {
            guard let name = deviceName(dev), name.localizedCaseInsensitiveContains(needle) else {
                continue
            }
            return dev
        }
        return nil
    }

    static func outputDeviceNames() -> [String] {
        outputDevices().compactMap(deviceName).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private static func outputDevices() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
        else { return [] }
        var devices = [AudioDeviceID](
            repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devices) == noErr
        else { return [] }
        return devices.filter(deviceHasOutput)
    }

    static func deviceExists(_ needle: String) -> Bool {
        findOutputDevice(nameContains: needle) != nil
    }

    static func deviceName(_ dev: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &name) == noErr else {
            return nil
        }
        return name?.takeRetainedValue() as String?
    }

    private static func deviceHasOutput(_ dev: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let ptr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { ptr.deallocate() }
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, ptr) == noErr else {
            return false
        }
        let list = UnsafeMutableAudioBufferListPointer(
            ptr.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }
}
