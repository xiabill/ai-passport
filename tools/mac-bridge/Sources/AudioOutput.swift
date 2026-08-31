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
    var renderCalls = 0
    private var pushes = 0

    init() {
        sourceNode = AVAudioSourceNode(format: format) {
            [weak self] isSilence, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let out = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let n = Int(frameCount)
            self.lock.lock()
            self.renderCalls += 1
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
        engine.attach(sourceNode)
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.rebuild()
        }
        try connectAndStart()
    }

    private func connectAndStart() throws {
        guard let deviceID = Self.findOutputDevice(nameContains: deviceName) else {
            throw NSError(
                domain: "FoloVibeBridge", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "missing output device \(deviceName)"]
            )
        }
        try engine.outputNode.auAudioUnit.setDeviceID(deviceID)
        engine.connect(sourceNode, to: engine.outputNode, format: format)
        if !engine.isRunning { try engine.start() }
    }

    private func rebuild() {
        engine.stop()
        engine.reset()
        try? connectAndStart()
        lock.lock()
        primed = false
        lock.unlock()
    }

    func push(_ samples: [Int16]) {
        lock.lock()
        pushes += 1
        for s in samples { fifo.append(Float(s) / 32768.0) }
        if fifo.count > maxFrames { fifo.removeFirst(fifo.count - maxFrames) }
        lock.unlock()
    }

    static func findOutputDevice(nameContains needle: String) -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
        else { return nil }
        var devices = [AudioDeviceID](
            repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devices) == noErr
        else { return nil }
        for dev in devices {
            guard deviceHasOutput(dev), let name = deviceName(dev), name.contains(needle) else {
                continue
            }
            return dev
        }
        return nil
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
