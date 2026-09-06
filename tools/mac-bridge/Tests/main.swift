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
    expect(VibeEvent.doubaoStart.rawValue == 5, "Doubao start event")
    expect(VibeEvent.doubaoStopAndSend.rawValue == 7, "Doubao stop-send event")
    expect(VibeEvent.doubaoSelectAll.rawValue == 10, "Doubao select-all event")
    expect(VibeEvent.doubaoClear.rawValue == 11, "Doubao clear event")
    expect(VibeEvent.typelessTranslate.rawValue == 8, "Typeless translation event")
    expect(VibeEvent.typelessAsk.rawValue == 9, "Typeless Ask anything event")
}

do {
    expect(BridgeSettings.default.talk.name == "Fn", "default talk key")
    expect(BridgeSettings.default.talk.carbon == 0x3F, "Fn carbon")
    expect(BridgeSettings.default.doubao.name == "Right Option", "default Doubao key")
    expect(BridgeSettings.default.doubao.carbon == 0x3D, "Right Option carbon")
    expect(BridgeSettings.default.powerMode == .standard, "default standard power mode")
    var s = BridgeSettings.default
    s.talkKey = "Nope"
    expect(s.talk.name == "Fn", "unknown key fallback")
    let ud = UserDefaults(suiteName: "folovibe.tests.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: ud)
    store.current.talkKey = "F18"
    store.current.doubaoKey = "Left Option"
    let again = SettingsStore(defaults: ud)
    expect(again.current.talkKey == "F18", "settings round trip")
    expect(again.current.doubaoKey == "Left Option", "Doubao setting round trip")
    store.current.powerMode = .eco
    let powerAgain = SettingsStore(defaults: ud)
    expect(powerAgain.current.powerMode == .eco, "power mode round trip")
    expect(Hotkey.named("F17", in: Hotkey.talkKeys, fallback: Hotkey.talkKeys[0]).carbon == 0x40, "F17 lookup")
    expect(Hotkey.named("Fn", in: Hotkey.talkKeys, fallback: Hotkey.talkKeys[0]).carbon == 0x3F, "Fn lookup")
    expect(Hotkey.named("Right Option", in: Hotkey.doubaoKeys, fallback: Hotkey.doubaoKeys[0]).carbon == 0x3D, "Doubao lookup")
    expect(VibeProtocol.powerModeStandard == 0x80, "standard power command")
    expect(VibeProtocol.powerModeEco == 0x81, "eco power command")
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
    let map = ButtonMap.default
    expect(map.action(.up, .click) == .doubao, "default up click drives Doubao")
    expect(map.action(.mid, .click) == .enter, "default mid click confirms")
    expect(map.action(.down, .click) == .typelessDictate, "default down click dictates")
    expect(map.action(.down, .double) == .typelessTranslate, "default down double translates")
    expect(map.action(.down, .long) == .typelessAsk, "default down long asks")
    expect(map.action(.mid, .long) == .none, "unbound gesture defaults to none")

    var custom = ButtonMap.default
    custom.set(.mid, .long, .typelessAsk)
    expect(custom.action(.mid, .long) == .typelessAsk, "rebinding sticks")

    // Wire order must be gesture index = key * 3 + gesture.
    let codes = custom.actionCodes
    expect(codes.count == 9, "nine action codes")
    expect(codes[ButtonKey.down.rawValue * 3 + ButtonGesture.click.rawValue] == 1, "dictate code")
    expect(codes[ButtonKey.mid.rawValue * 3 + ButtonGesture.long.rawValue] == 3, "ask code")
    expect(codes[ButtonKey.up.rawValue * 3 + ButtonGesture.click.rawValue] == 4, "Doubao code")
    expect(codes[ButtonKey.mid.rawValue * 3 + ButtonGesture.click.rawValue] == 5, "Return code")

    expect(ButtonAction.typelessDictate.isRecording, "dictate records")
    expect(ButtonAction.doubao.isRecording, "Doubao records")
    expect(!ButtonAction.enter.isRecording, "Return does not record")
    expect(ButtonAction.typelessAsk.isTypeless, "ask is Typeless-backed")

    // Only the same input method may end a take (mirrors VIBE_ACT_SAME_INPUT).
    expect(
        ButtonAction.typelessDictate.drivesSameInput(as: .typelessTranslate),
        "Typeless modes share one input method")
    expect(
        !ButtonAction.typelessDictate.drivesSameInput(as: .doubao),
        "Typeless and Doubao are separate input methods")
    expect(ButtonAction.doubao.drivesSameInput(as: .doubao), "Doubao stops itself")
    expect(!ButtonAction.doubao.isTypeless, "Doubao is not Typeless-backed")

    // Gesture wire encoding: 0x20 | (button << 2) | gesture.
    expect(GestureEvent.parse(0x24) == GestureEvent(key: .mid, gesture: .click), "0x24 = mid click")
    expect(GestureEvent.parse(0x20) == GestureEvent(key: .up, gesture: .click), "0x20 = up click")
    expect(GestureEvent.parse(0x2A) == GestureEvent(key: .down, gesture: .long), "0x2A = down long")
    expect(GestureEvent.parse(0x19) == nil, "reject non-gesture byte")

    let ud = UserDefaults(suiteName: "folovibe.buttons.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: ud)
    store.current.buttons.set(.up, .long, .enter)
    expect(SettingsStore(defaults: ud).current.buttons.action(.up, .long) == .enter,
        "bindings round trip")
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
