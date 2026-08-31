import Combine
import FoloVibeCore
import Foundation

enum AppTab: String, CaseIterable {
    case status = "状态"
    case settings = "设置"
    case logs = "日志"
    case debug = "调试"
}

final class AppModel: ObservableObject {
    static let shared = AppModel()

    let settings = SettingsStore()
    let audio = AudioOutput()
    let mic = MicTest()
    let typeless = TypelessWatch()
    let logFilter = LogFilter()
    private(set) var ble: BLEClient!

    @Published var tab: AppTab = .status
    @Published var bleSnap = BLEClient.Snapshot()
    @Published var typelessState: TypelessState = .down
    @Published var audioPeak: Int = 0
    @Published var axOK = false
    @Published var blackholeOK = false
    @Published var typelessMicLabel = "—"
    @Published var typelessMicOK = false
    @Published var loginOn = false
    @Published var lastAction = "—"
    @Published var debugNote = ""

    private var expect: TypelessState = .idle
    private var lastHotkey = Date.distantPast
    private var retaps = 0
    private var lastOutput = ""
    private var lastPrefix = ""
    private var lastTypelessPoll = Date.distantPast

    private init() {}

    func start() {
        ble = BLEClient(audio: audio, mic: mic)
        ble.prefix = settings.current.devicePrefix
        ble.autoReconnect = settings.current.autoReconnect
        ble.onEvent = { [weak self] ev in self?.handle(ev) }
        applyAudio()
        axOK = KeyTap.trusted
        if !axOK { Log.sys("辅助功能未开，按键无法发给 Typeless") }
        let mic = Permissions.typelessMicLabel()
        typelessMicLabel = mic ?? "未读取"
        if let mic, !Permissions.typelessMicOK(settings.current.outputDevice) {
            Log.typeless("当前麦克风是 \(mic)，应改为 \(settings.current.outputDevice)")
        }
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        Log.sys("FoloVibe 已启动")
    }

    func applyAudio() {
        lastOutput = settings.current.outputDevice
        do {
            try audio.start(deviceNameContains: settings.current.outputDevice)
            blackholeOK = true
        } catch {
            blackholeOK = false
            Log.audio(error.localizedDescription)
        }
    }

    func handle(_ ev: VibeEvent) {
        lastAction = ev.title
        let s = settings.current
        switch ev {
        case .start:
            KeyTap.tap(s.talk)
            expect = .recording
            lastHotkey = Date()
            retaps = 0
        case .stop:
            KeyTap.tap(s.talk)
            expect = .idle
            lastHotkey = Date()
            retaps = 0
        case .enter:
            KeyTap.tap(s.send)
        case .cancel:
            if ble.snapshot.streaming { KeyTap.tap(s.talk) }
            KeyTap.tap(s.cancel)
            expect = .idle
            lastHotkey = Date()
        }
    }

    func simulate(_ ev: VibeEvent) {
        Log.debug("模拟 \(ev.title)")
        handle(ev)
    }

    private func tick() {
        if ble.prefix != settings.current.devicePrefix {
            ble.prefix = settings.current.devicePrefix
            ble.reconnect()
        }
        ble.autoReconnect = settings.current.autoReconnect
        if lastOutput != settings.current.outputDevice { applyAudio() }

        bleSnap = ble.snapshot
        audioPeak = audio.peak
        axOK = KeyTap.trusted
        blackholeOK = AudioOutput.deviceExists(settings.current.outputDevice)
        typelessMicLabel = Permissions.typelessMicLabel() ?? "未读取"
        typelessMicOK = Permissions.typelessMicOK(settings.current.outputDevice)
        loginOn = LoginItem.enabled

        let interval = max(0.5, settings.current.typelessPollSec)
        let hot = bleSnap.streaming
        if hot || Date().timeIntervalSince(lastTypelessPoll) >= interval {
            lastTypelessPoll = Date()
            let st = typeless.poll()
            if st != typelessState {
                Log.typeless(st.title)
                typelessState = st
            }
            ble.writeTypeless(st.rawValue)
            closedLoop(st)
        }
    }

    private func closedLoop(_ st: TypelessState) {
        let s = settings.current
        guard s.retapEnabled, typeless.running, retaps < s.retapMax else { return }
        let dt = Date().timeIntervalSince(lastHotkey)
        guard dt >= s.retapFromSec, dt <= s.retapToSec else { return }
        if expect == .recording && st != .recording {
            Log.typeless("补按开始键，Typeless 仍是 \(st.title)")
            KeyTap.tap(s.talk)
            lastHotkey = Date()
            retaps += 1
        } else if expect == .idle && st == .recording {
            Log.typeless("补按停止键")
            KeyTap.tap(s.talk)
            lastHotkey = Date()
            retaps += 1
        }
    }
}
