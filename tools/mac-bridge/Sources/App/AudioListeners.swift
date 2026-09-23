import AppKit
import CoreAudio

/// Which applications are recording right now, and from which input devices.
/// The bridge can only put audio into the virtual device; whether anything is
/// listening on the other side was invisible, and a dictation app quietly
/// listening to a desk microphone went unnoticed for a long time because of it.
enum AudioListeners {
    struct Listener {
        let app: String
        let devices: [String]
    }

    /// Nil where the system cannot say (before macOS 14.2).
    static func current() -> [Listener]? {
        guard #available(macOS 14.2, *) else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        var out = [Listener]()
        for process in ids(AudioObjectID(kAudioObjectSystemObject),
                           kAudioHardwarePropertyProcessObjectList) {
            let pid: pid_t = value(process, kAudioProcessPropertyPID, 0)
            let recording: UInt32 = value(process, kAudioProcessPropertyIsRunningInput, 0)
            guard pid != me, recording != 0 else { continue }
            let devices = ids(process, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeInput)
                .compactMap(AudioOutput.deviceName)
            let app = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "进程 \(pid)"
            out.append(Listener(app: app, devices: devices))
        }
        return out
    }

    private static func value<T>(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                 _ fallback: T) -> T {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var v = fallback
        var size = UInt32(MemoryLayout<T>.size)
        AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &v)
        return v
    }

    private static func ids(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector,
                            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> [AudioObjectID]
    {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &addr, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &list)
        return list
    }
}
