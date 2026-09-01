import Combine
import FoloVibeCore
import Foundation

enum AppTab: String, CaseIterable, Hashable {
    case status = "状态"
    case settings = "设置"
    case logs = "日志"
    case debug = "调试"

    var title: String { rawValue }

    var subtitle: String {
        switch self {
        case .status: return "连接与运行状态"
        case .settings: return "输入法与设备偏好"
        case .logs: return "查看事件与错误"
        case .debug: return "诊断与硬件测试"
        }
    }

    var symbol: String {
        switch self {
        case .status: return "rectangle.3.group"
        case .settings: return "slider.horizontal.3"
        case .logs: return "text.alignleft"
        case .debug: return "wrench.and.screwdriver"
        }
    }
}

final class AppModel: ObservableObject {
    enum ActiveInput: String {
        case typeless = "Typeless"
        case typelessTranslate = "Typeless 翻译"
        case typelessAsk = "Typeless 随便问"
        case doubao = "豆包"

        var isTypeless: Bool {
            self != .doubao
        }
    }

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
    @Published var activeInputTitle = "—"
    @Published var audioDeviceNames: [String] = []
    @Published var audioTestNote = "尚未测试"
    @Published var repairNote = ""

    private var expect: TypelessState = .idle
    private var lastHotkey = Date.distantPast
    private var retaps = 0
    private var lastOutput = ""
    private var lastPrefix = ""
    private var lastTypelessPoll = Date.distantPast
    private var activeInput: ActiveInput?
    private var lastMicWarning = ""

    private init() {}

    func start() {
        ble = BLEClient(audio: audio, mic: mic)
        ble.prefix = settings.current.devicePrefix
        ble.autoReconnect = settings.current.autoReconnect
        ble.onEvent = { [weak self] ev in self?.handle(ev) }
        applyAudio()
        refreshChecks()
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        Log.sys("FoloVibe 已启动")
    }

    /// Refresh permission and setup checks after the user returns from a system
    /// settings page. The timer also calls this, but exposing it makes the
    /// guided setup flow explicit and immediately responsive.
    func refreshChecks() {
        let wasAXOK = axOK
        axOK = KeyTap.trusted
        audioDeviceNames = AudioOutput.outputDeviceNames()
        blackholeOK = AudioOutput.deviceExists(settings.current.outputDevice)
        typelessMicLabel = Permissions.typelessMicLabel() ?? "未读取"
        typelessMicOK = Permissions.typelessMicOK(settings.current.outputDevice)
        loginOn = LoginItem.enabled

        if wasAXOK != axOK {
            Log.sys(axOK ? "辅助功能已授权，可以发送快捷键" : "辅助功能未开，按键无法发给 Typeless")
        }
        if !typelessMicOK, typelessMicLabel != "未读取", typelessMicLabel != lastMicWarning {
            Log.typeless("当前麦克风是 \(typelessMicLabel)，应改为 \(settings.current.outputDevice)")
            lastMicWarning = typelessMicLabel
        } else if typelessMicOK {
            lastMicWarning = ""
        }
    }

    /// Fixes the first blocking setup item and stops so the user can observe
    /// the result. Permissions and third-party installation remain explicit;
    /// safe local repairs, such as selecting an already-installed BlackHole
    /// device or restarting a BLE scan, happen automatically.
    func repairSetup() {
        refreshChecks()
        bleSnap = ble.snapshot
        if !axOK {
            Permissions.openAccessibility()
            KeyTap.promptTrust()
            repairNote = "已打开辅助功能设置：请打开 FoloVibe Bridge，再点“再次检查”。"
            return
        }
        if !bleSnap.bluetoothOn {
            Permissions.openBluetooth()
            repairNote = "已打开蓝牙设置；开启后点“再次检查”。"
            return
        }
        if !bleSnap.subscribed {
            ble.reconnect()
            repairNote = "已重新扫描 Passport；请保持设备开机并靠近 Mac。"
            return
        }
        if !blackholeOK {
            if let installed = audioDeviceNames.first(where: {
                $0.localizedCaseInsensitiveContains("blackhole")
            }) {
                settings.current.outputDevice = installed
                applyAudio()
                repairNote = "已切换到已安装的 (installed)，正在重新检查音频链路。"
            } else {
                Permissions.openBlackHoleDownload()
                repairNote = "未检测到 BlackHole，已打开官方安装页；安装后点“再次检查”。"
            }
            return
        }
        if !typeless.running {
            _ = Permissions.openTypeless()
            repairNote = "已尝试打开 Typeless；启动后点“再次检查”。"
            return
        }
        if !typelessMicOK {
            _ = Permissions.openTypeless()
            repairNote = "已打开 Typeless，请在“语音输入”中选择 (settings.current.outputDevice)，再点“再次检查”。"
            return
        }
        repairNote = "检查完成，没有发现需要修复的项目。"
    }

    func playAudioTest() {
        guard blackholeOK else {
            audioTestNote = "无法测试：请先选择可用的音频输出设备。"
            return
        }
        audio.playTestTone()
        audioTestNote = "已播放 2 秒测试音；请确认音频包计数或目标软件有反应。"
    }

    func toggleMicTest() {
        if mic.isArmed {
            mic.cancel()
        } else {
            mic.arm()
        }
        audioTestNote = mic.result
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
            activeInput = .typeless
            activeInputTitle = ActiveInput.typeless.rawValue
            expect = .recording
            lastHotkey = Date()
            retaps = 0
        case .typelessTranslate:
            KeyTap.tapTypelessTranslate(s.talk)
            activeInput = .typelessTranslate
            activeInputTitle = ActiveInput.typelessTranslate.rawValue
            expect = .recording
            lastHotkey = Date()
            retaps = 0
        case .typelessAsk:
            KeyTap.tapTypelessAsk(s.talk)
            activeInput = .typelessAsk
            activeInputTitle = ActiveInput.typelessAsk.rawValue
            expect = .recording
            lastHotkey = Date()
            retaps = 0
        case .stop:
            KeyTap.tap(s.talk)
            activeInput = .typeless
            activeInputTitle = ActiveInput.typeless.rawValue
            expect = .idle
            lastHotkey = Date()
            retaps = 0
        case .enter:
            KeyTap.tap(s.send)
        case .cancel:
            if ble.snapshot.streaming { KeyTap.tap(s.talk) }
            KeyTap.tap(s.cancel)
            activeInput = nil
            activeInputTitle = "—"
            expect = .idle
            lastHotkey = Date()
        case .doubaoStart:
            KeyTap.tap(s.doubao)
            activeInput = .doubao
            activeInputTitle = ActiveInput.doubao.rawValue
        case .doubaoStop:
            KeyTap.tap(s.doubao)
            activeInput = nil
            activeInputTitle = "—"
        case .doubaoStopAndSend:
            KeyTap.tap(s.doubao)
            activeInput = nil
            activeInputTitle = "—"
            Log.key("豆包停止后延迟发送回车")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                KeyTap.tap(self.settings.current.send)
            }
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
        refreshChecks()
        if mic.result != "未测试" { audioTestNote = mic.result }

        let interval = max(0.5, settings.current.typelessPollSec)
        let hot = bleSnap.streaming
        if hot || Date().timeIntervalSince(lastTypelessPoll) >= interval {
            lastTypelessPoll = Date()
            let st = typeless.poll()
            if st != typelessState {
                Log.typeless(st.title)
                typelessState = st
            }
            if activeInput?.isTypeless == true && !bleSnap.streaming && st == .idle {
                activeInput = nil
                activeInputTitle = "—"
            }
            ble.writeTypeless(st.rawValue)
            closedLoop(st)
        }
    }

    private func closedLoop(_ st: TypelessState) {
        let s = settings.current
        guard activeInput?.isTypeless == true, s.retapEnabled, typeless.running, retaps < s.retapMax
        else { return }
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
