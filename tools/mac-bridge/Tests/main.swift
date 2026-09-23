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
}

do {
    expect(BridgeSettings.default.powerMode == .standard, "default standard power mode")
    // codes must stay consecutive.
    expect(VibeProtocol.powerModeEco == VibeProtocol.powerModeStandard + 1, "eco follows standard")
    expect(VibeProtocol.powerModeUltra == VibeProtocol.powerModeStandard + 2, "ultra follows eco")
    expect(BridgePowerMode.allCases.count == 3, "three power modes")
    expect(BridgePowerMode.ultra.title == "超级省电", "ultra title")
}

do {
    // A setup written when the app knew about particular input methods keeps
    // working: the keys that lived in settings move onto the gestures that
    // were sending them, double press and all. Without this an upgrade would
    // leave every button silent until each one was recorded again.
    let legacy = Data(#"""
    {"talkKey":"F13","doubaoKey":"Right Option","talkTap":"single","doubaoTap":"double",
     "buttons":{"bindings":{"0.0":"doubao","2.0":"typelessDictate","1.0":"enter"}}}
    """#.utf8)
    let old = try? JSONDecoder().decode(BridgeSettings.self, from: legacy)
    expect(old?.buttons.action(.up, .click) == .voice, "Doubao binding becomes voice input")
    expect(old?.buttons.stroke(.up, .click)?.keyCode == 0x3D, "and keeps Right Option")
    expect(old?.buttons.stroke(.up, .click)?.style == .double, "and its double press")
    expect(old?.buttons.stroke(.down, .click)?.keyCode == 0x69, "dictation keeps F13")
    expect(old?.buttons.stroke(.down, .click)?.style == .tap, "as a single press")
    // Return used to be an action of its own; it is the same key, now carried
    // by the gesture, so the binding keeps working without being re-made.
    expect(old?.buttons.action(.mid, .click) == .key, "Return becomes a sent key")
    expect(old?.buttons.stroke(.mid, .click)?.keyCode == 0x24, "carrying Return itself")
    expect(old?.buttons.label(.mid, .click) == "发送", "and naming the key on screen")

    // The retired keys are read once and never written back.
    let saved = try? JSONEncoder().encode(old ?? .default)
    let text = String(decoding: saved ?? Data(), as: UTF8.self)
    expect(!text.contains("talkKey") && !text.contains("doubaoTap"),
        "retired settings are not written again")
}

do {
    // A key with no name of its own is still named on the device: the preset
    // it matches, else the key itself, never a bare "custom".
    var map = ButtonMap()
    map.set(.mid, .click, .key)
    map.setStroke(.mid, .click, KeyStroke(keyCode: 0x24, modifiers: 0, label: "↩"))
    expect(map.screenName(.mid, .click) == "发送", "Return is named after its preset")
    map.setStroke(.mid, .click, KeyStroke(keyCode: 0x23, modifiers: KeyStroke.command | KeyStroke.shift, label: "⇧⌘P"))
    expect(map.screenName(.mid, .click) == "⇧⌘P", "an unknown key is named by itself")
    map.setLabel(.mid, .click, "命令")
    expect(map.screenName(.mid, .click) == "命令", "the user's own name wins")
    expect(ButtonMap().screenName(.up, .click) == nil, "nothing bound, nothing named")
}

do {
    // Presets are just named strokes, so picking one fills the same field the
    // recorder would — and names the key on the device at the same time.
    var map = ButtonMap()
    map.bind(.up, .double, preset: "copy")
    expect(map.action(.up, .double) == .key, "a preset is a sent key")
    expect(map.stroke(.up, .double)?.modifiers == KeyStroke.command, "copy carries Command")
    expect(map.label(.up, .double) == "复制", "and labels the key on the device")
    expect(KeyPreset.find("playPause")?.stroke.isMedia == true,
        "media keys are marked, since they do not travel as key events")
    expect(KeyPreset.all.count == Set(KeyPreset.all.map(\.id)).count, "preset ids are unique")
    expect(KeyPreset.Group.allCases.allSatisfy { !KeyPreset.grouped($0).isEmpty },
        "every group has something in it")

    // How a key is sent survives a save, and an older stroke reads as a tap.
    var s = KeyStroke(keyCode: 8, modifiers: 0, label: "C", style: .hold)
    let round = try? JSONDecoder().decode(KeyStroke.self, from: JSONEncoder().encode(s))
    expect(round?.style == .hold, "hold survives a round trip")
    let older = Data(#"{"keyCode":8,"modifiers":0,"label":"C","taps":2}"#.utf8)
    expect((try? JSONDecoder().decode(KeyStroke.self, from: older))?.style == .double,
        "a stroke written before styles reads as a double press")
    s.style = .tap
    expect(s.display == "C" , "a plain tap shows just the key")
}

do {
    // A screen label is trimmed, and blank means "use the built-in name".
    var map = ButtonMap.default
    map.setLabel(.up, .click, "  讯飞 ")
    expect(map.label(.up, .click) == "讯飞", "label is trimmed")
    map.setLabel(.up, .click, "   ")
    expect(map.label(.up, .click) == nil, "blank label falls back to the default")
    map.setLabel(.down, .long, "问问")
    let round = try? JSONDecoder().decode(ButtonMap.self, from: JSONEncoder().encode(map))
    expect(round?.label(.down, .long) == "问问", "label round trips")
    // Wire slots follow the firmware's gesture index: button * 3 + gesture.
    expect(ButtonMap.wireSlot(.mid, .double) == 4, "wire slot matches firmware")
    // Configurations written before labels existed still decode.
    let legacy = Data(#"{"bindings":{"0.0":"doubao"}}"#.utf8)
    let old = try? JSONDecoder().decode(ButtonMap.self, from: legacy)
    expect(old?.action(.up, .click) == .voice && old?.label(.up, .click) == nil,
           "legacy button map has no labels")
}

do {
    // Handing a device to another Mac never arms the microphone, and its wire
    // code must not collide with anything the firmware already knows.
    expect(ButtonAction.handoff.code == 10, "handoff wire code")
    expect(!ButtonAction.handoff.isRecording, "handoff does not record")
    expect(Set(ButtonAction.allCases.map(\.code)).count == ButtonAction.allCases.count,
           "every action has its own wire code")
}

do {
    expect(ButtonAction.key.code == 9, "send-key wire code")
    expect(!ButtonAction.key.isRecording, "sending a key does not record")
    expect(KeyStroke.label(keyCode: 8, modifiers: KeyStroke.command, keyName: "C") == "⌘C",
        "label puts the symbol before the key")
    expect(KeyStroke.label(keyCode: 8,
        modifiers: KeyStroke.command | KeyStroke.shift | KeyStroke.option | KeyStroke.control,
        keyName: "C") == "⌃⌥⇧⌘C", "modifiers use the conventional order")

    var map = ButtonMap.default
    map.set(.down, .double, .key)
    map.setStroke(.down, .double, KeyStroke(keyCode: 8, modifiers: KeyStroke.command, label: "⌘C"))
    expect(map.stroke(.down, .double)?.label == "⌘C", "stroke stored per slot")
    expect(map.stroke(.up, .click) == nil, "other slots keep no stroke")

    // Configurations written before custom keys existed must still decode.
    let legacy = Data("""
    {"bindings":{"1.0":"enter"}}
    """.utf8)
    let decoded = try? JSONDecoder().decode(ButtonMap.self, from: legacy)
    expect(decoded?.action(.mid, .click) == .key, "legacy config still decodes")
    expect(decoded?.stroke(.mid, .click)?.keyCode == 0x24, "and gains the key it used to mean")

    let round = try? JSONDecoder().decode(
        ButtonMap.self, from: JSONEncoder().encode(map))
    expect(round?.stroke(.down, .double)?.keyCode == 8, "stroke round trips")
}

do {
    let h = VibeProtocol.otaHeader(length: 1216672)
    expect(h.count == 6, "OTA header is six bytes")
    expect(h[0] == 0x46 && h[1] == 0x57, "OTA header magic")
    let len = UInt32(h[2]) | (UInt32(h[3]) << 8) | (UInt32(h[4]) << 16) | (UInt32(h[5]) << 24)
    expect(len == 1216672, "OTA header carries the length little-endian")
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
