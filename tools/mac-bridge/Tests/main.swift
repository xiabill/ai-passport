import FoloVibeCore
import Foundation

var failed = 0

func expect(_ cond: Bool, _ name: String) {
    if cond {
        print("OK  \(name)")
    } else {
        print("FAIL \(name)")
        failed += 1
    }
}

do {
    let pcm = IMAADPCM.decode(Data([0x04, 0x0C]), predictor: 0, stepIndex: 0)
    expect(Array(pcm.prefix(3)) == [7, 8, -1], "ADPCM reference vector")
    expect(IMAADPCM.peak([12, -40, 7]) == 40, "ADPCM peak")
}

do {
    var bytes = [UInt8](repeating: 0, count: 166)
    bytes[0] = 0x34
    bytes[1] = 0x12
    bytes[2] = 0xFE
    bytes[3] = 0xFF
    bytes[4] = 7
    bytes[6] = 0xA5
    let pkt = AudioPacket.parse(Data(bytes))
    expect(pkt?.seq == 0x1234, "packet seq")
    expect(pkt?.predictor == -2, "packet predictor")
    expect(pkt?.eos == false, "packet not eos")
    expect(AudioPacket.parse(Data([9, 0, 0, 0, 0, 1]))?.eos == true, "eos packet")
    expect(AudioPacket.parse(Data([1, 2, 3, 4, 5])) == nil, "reject short")
    expect(VibeEvent.start.rawValue == 1, "event start")
}

do {
    expect(BridgeSettings.default.talk.name == "F19", "default talk key")
    expect(BridgeSettings.default.talk.carbon == 0x50, "F19 carbon")
    var s = BridgeSettings.default
    s.talkKey = "Nope"
    expect(s.talk.name == "F19", "unknown key fallback")
    let ud = UserDefaults(suiteName: "folovibe.tests.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: ud)
    store.current.talkKey = "F18"
    let again = SettingsStore(defaults: ud)
    expect(again.current.talkKey == "F18", "settings round trip")
    expect(Hotkey.named("F17", in: Hotkey.talkKeys, fallback: Hotkey.talkKeys[0]).carbon == 0x40, "F17 lookup")
}

do {
    expect(
        TypelessState.derive(running: false, hasRow: true, statusNull: true, durationNull: true)
            == .down, "typeless down")
    expect(
        TypelessState.derive(running: true, hasRow: true, statusNull: true, durationNull: true)
            == .recording, "typeless recording")
    expect(
        TypelessState.derive(running: true, hasRow: true, statusNull: true, durationNull: false)
            == .processing, "typeless processing")
    expect(
        TypelessState.derive(running: true, hasRow: true, statusNull: false, durationNull: false)
            == .idle, "typeless idle")
    expect(
        TypelessState.derive(running: true, hasRow: false, statusNull: true, durationNull: true)
            == .idle, "typeless empty")
}

do {
    let line = LogLine.parse("01:02:03.456 [蓝牙] 已连接 FoloVibe-4C11")
    expect(line.time == "01:02:03.456", "log time")
    expect(line.category == "蓝牙", "log category")
    expect(line.message == "已连接 FoloVibe-4C11", "log message")
    expect(LogLine.parse("裸行没有分类").category.isEmpty, "bare log line")
}

if failed == 0 {
    print("ALL PASSED")
    exit(0)
}
print("\(failed) FAILED")
exit(1)
