import AppKit
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
    static let shared = AppModel()

    let settings = SettingsStore()
    let audio = AudioOutput()
    let mic = MicTest()
    let typeless = TypelessWatch()
    let logFilter = LogFilter()
    let updater = Updater()
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
    @Published var captureTarget: KeyCaptureTarget?
    /// Which grid slot is currently recording a custom shortcut.
    @Published var strokeTarget: GestureSlot?
    @Published var firmwareVersion = "—"
    @Published var otaProgress: Double = 0
    @Published var otaNote = ""
    @Published var otaRunning = false
    @Published var audioDeviceNames: [String] = []
    @Published var audioTestNote = "尚未测试"
    @Published var repairNote = ""

    private var expect: TypelessState = .idle
    private var lastHotkey = Date.distantPast
    private var retaps = 0
    private var lastOutput = ""
    private var lastPrefix = ""
    private var lastTypelessPoll = Date.distantPast
    private var lastEnvCheck = Date.distantPast
    private var awaitingTranscript = false

    /// refreshChecks() enumerates every CoreAudio device and reads the Typeless
    /// settings file; far too costly for the 0.5 s UI tick.
    private static let envCheckSec: TimeInterval = 5
    private var appliedPowerMode: BridgePowerMode?
    private var activeInput: ButtonAction?
    private var pendingEnter = false
    private var appliedButtons = ButtonMap.default
    private var lastMicWarning = ""

    private init() {}

    func start() {
        ble = BLEClient(audio: audio, mic: mic)
        ble.prefix = settings.current.devicePrefix
        ble.autoReconnect = settings.current.autoReconnect
        ble.setPowerMode(settings.current.powerMode)
        appliedPowerMode = settings.current.powerMode
        ble.onEvent = { [weak self] ev in self?.handle(ev) }
        ble.onGesture = { [weak self] g in self?.handleGesture(g) }
        ble.onFirmwareVersion = { [weak self] v in self?.firmwareVersion = v }
        ble.onOTAProgress = { [weak self] p in self?.otaProgress = p }
        ble.onOTAFinished = { [weak self] err in
            guard let self else { return }
            self.otaRunning = false
            self.otaNote = err ?? "固件已发送，设备正在校验并重启"
            Log.sys(self.otaNote)
        }
        ble.writeActions(settings.current.buttons.actionCodes)
        applyAudio()
        refreshChecks()
        followTypelessIfStranded()
        // Quiet check on launch; the settings page shows the result.
        updater.check(quiet: true)
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
        if !blackholeOK || !typelessMicOK {
            autoPairAudio()
            return
        }
        if !typeless.running {
            _ = Permissions.openTypeless()
            repairNote = "已尝试打开 Typeless；启动后点“再次检查”。"
            return
        }
        repairNote = "检查完成，没有发现需要修复的项目。"
    }

    /// Picks an audio device that both sides can actually use and configures
    /// them together. A loopback device that CoreAudio reports is useless if
    /// Typeless cannot enumerate it, so the choice is the intersection of the
    /// two lists rather than a hardcoded BlackHole.
    /// Loopback devices that both CoreAudio and Typeless can see. Exposed so
    /// the setup guide can tell the user what it is about to pick.
    var usableLoopbacks: [String] {
        let visible = Permissions.typelessVisibleMicLabels()
        return AudioOutput.loopbackDeviceNames().filter { device in
            visible.contains { $0.caseInsensitiveCompare(device) == .orderedSame }
        }
    }

    /// If the bridge points at a device Typeless cannot use, follow whatever
    /// Typeless already selected. Only our own setting is touched, so this is
    /// safe to run unattended at launch — unlike autoPairAudio(), which may
    /// restart Typeless to write its config.
    func followTypelessIfStranded() {
        let usable = usableLoopbacks
        guard !usable.isEmpty, let mic = Permissions.typelessMicLabel() else { return }
        let currentWorks = usable.contains {
            $0.caseInsensitiveCompare(settings.current.outputDevice) == .orderedSame
        }
        guard !currentWorks,
            usable.contains(where: { $0.caseInsensitiveCompare(mic) == .orderedSame })
        else { return }
        Log.audio("输出设备 \(settings.current.outputDevice) 不可用，跟随 Typeless 改用 \(mic)")
        settings.current.outputDevice = mic
        applyAudio()
    }

    func autoPairAudio() {
        let loopbacks = AudioOutput.loopbackDeviceNames()
        let visible = Permissions.typelessVisibleMicLabels()
        let usable = loopbacks.filter { device in
            visible.contains { $0.caseInsensitiveCompare(device) == .orderedSame }
        }

        guard let pick = preferredLoopback(usable) else {
            if loopbacks.isEmpty {
                Permissions.openBlackHoleDownload()
                repairNote = "没有找到任何回环音频设备，已打开 BlackHole 安装页；安装后点“再次检查”。"
            } else if visible.isEmpty {
                _ = Permissions.openTypeless()
                repairNote = "还读不到 Typeless 的设备列表，请先打开 Typeless 再点“自动修复”。"
            } else {
                repairNote = "系统里有 \(loopbacks.joined(separator: "、"))，但 Typeless 一个都枚举不到。"
                    + "请退出并重新打开 Typeless；若仍然如此，改用它能看到的回环设备。"
            }
            refreshChecks()
            return
        }

        if settings.current.outputDevice != pick {
            settings.current.outputDevice = pick
            applyAudio()
        }
        if Permissions.typelessMicLabel()?.caseInsensitiveCompare(pick) == .orderedSame {
            repairNote = "音频链路已对齐：Bridge 与 Typeless 都在用 \(pick)。"
            refreshChecks()
            return
        }
        pointTypelessAt(pick)
    }

    /// Keeps the user's existing choice when it still works, otherwise prefers
    /// BlackHole as the best-known device before falling back to any loopback.
    private func preferredLoopback(_ usable: [String]) -> String? {
        if let current = usable.first(where: {
            $0.caseInsensitiveCompare(settings.current.outputDevice) == .orderedSame
        }) { return current }
        if let blackhole = usable.first(where: {
            $0.localizedCaseInsensitiveContains("blackhole")
        }) { return blackhole }
        return usable.first
    }

    /// Typeless keeps its settings in memory and rewrites them on quit, so the
    /// file can only be edited while it is closed.
    private func pointTypelessAt(_ label: String) {
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: "now.typeless.desktop")
        guard !running.isEmpty else {
            applyTypelessMic(label)
            return
        }
        repairNote = "正在重启 Typeless 以写入麦克风设置…"
        running.forEach { $0.terminate() }
        waitForTypelessExit(retries: 20, label: label)
    }

    private func waitForTypelessExit(retries: Int, label: String) {
        guard Permissions.typelessRunning, retries > 0 else {
            applyTypelessMic(label)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.waitForTypelessExit(retries: retries - 1, label: label)
        }
    }

    private func applyTypelessMic(_ label: String) {
        let ok = Permissions.setTypelessMic(label)
        _ = Permissions.openTypeless()
        repairNote = ok
            ? "已把 Typeless 麦克风设为 \(label) 并重新打开它，链路配置完成。"
            : "无法写入 Typeless 设置，请在它的“语音输入”里手动选择 \(label)。"
        Log.typeless(repairNote)
        refreshChecks()
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
            setActiveInput(.typelessDictate)
            expect = .recording
            lastHotkey = Date()
            retaps = 0
        case .typelessTranslate:
            KeyTap.tapTypelessTranslate(s.talk)
            setActiveInput(.typelessTranslate)
            expect = .recording
            lastHotkey = Date()
            retaps = 0
        case .typelessAsk:
            KeyTap.tapTypelessAsk(s.talk)
            setActiveInput(.typelessAsk)
            expect = .recording
            lastHotkey = Date()
            retaps = 0
        case .stop:
            KeyTap.tap(s.talk)
            setActiveInput(.typelessDictate)
            expect = .idle
            lastHotkey = Date()
            retaps = 0
            awaitingTranscript = true
        case .enter:
            KeyTap.tap(s.send)
        case .doubaoStart:
            KeyTap.tapDouble(s.doubao)
            setActiveInput(.doubao)
        case .doubaoStop:
            KeyTap.tapDouble(s.doubao)
            setActiveInput(nil)
        case .doubaoStopAndSend:
            KeyTap.tapDouble(s.doubao)
            setActiveInput(nil)
            Log.key("豆包停止后延迟发送回车")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                KeyTap.tap(self.settings.current.send)
            }
        case .doubaoSelectAll:
            // The edit shortcut is intentionally destructive: after a double
            // press the user wants to discard the mistaken transcript and
            // immediately speak again, not leave the text merely selected.
            KeyTap.tapClearAll()
        case .doubaoClear:
            KeyTap.tapClearAll()
        }
    }

    private func setActiveInput(_ action: ButtonAction?) {
        activeInput = action
        activeInputTitle = action?.title ?? "—"
    }

    /// The device reports which button was pressed and how; the binding decides
    /// what that means. Rebinding therefore never needs a firmware flash.
    func handleGesture(_ gesture: GestureEvent) {
        let action = settings.current.buttons.action(gesture.key, gesture.gesture)
        let stroke = settings.current.buttons.stroke(gesture.key, gesture.gesture)
        if action == .none {
            lastAction = "\(gesture.title)（未绑定）"
        } else if action == .customKey {
            lastAction = "\(gesture.title) → \(stroke?.label ?? "自定义按键未录制")"
        } else {
            lastAction = "\(gesture.title) → \(action.title)"
        }
        Log.key(lastAction)
        perform(action, stroke: stroke)
    }

    private func perform(_ action: ButtonAction, stroke: KeyStroke? = nil) {
        switch action {
        case .none:
            break
        case .enter:
            sendReturn()
        case .doubaoSelectAll:
            KeyTap.tapSelectAll()
        case .doubaoClear:
            KeyTap.tapClearAll()
        case .newline:
            KeyTap.tapNewline()
        case .customKey:
            guard let stroke else {
                Log.key("这个手势绑定了自定义按键，但还没录制")
                return
            }
            KeyTap.tapStroke(stroke)
        case .typelessDictate, .typelessTranslate, .typelessAsk, .doubao:
            toggleRecording(action)
        }
    }

    /// The device already decided whether this press starts or stops a take, so
    /// the bridge mirrors that using the input it currently believes is live.
    private func toggleRecording(_ action: ButtonAction) {
        let s = settings.current
        if let current = activeInput {
            // Only the input method that is recording may stop itself. The
            // device applies the same rule, so a stray press on the other one
            // never cuts a take short.
            guard current.drivesSameInput(as: action) else {
                Log.key("忽略 \(action.title)：\(current.title) 正在录音")
                return
            }
            switch current {
            case .doubao: KeyTap.tapDouble(s.doubao)
            default: KeyTap.tap(s.talk)  // Typeless always stops on its base key
            }
            expect = .idle
            lastHotkey = Date()
            retaps = 0
            if current.isTypeless { awaitingTranscript = true }
            setActiveInput(nil)
            return
        }
        switch action {
        case .typelessDictate: KeyTap.tap(s.talk)
        case .typelessTranslate: KeyTap.tapTypelessTranslate(s.talk)
        case .typelessAsk: KeyTap.tapTypelessAsk(s.talk)
        case .doubao: KeyTap.tapDouble(s.doubao)
        default: return
        }
        setActiveInput(action)
        if action.isTypeless {
            expect = .recording
            lastHotkey = Date()
            retaps = 0
        }
    }

    /// Return must land after the transcript, never in the middle of it.
    private func sendReturn() {
        if awaitingTranscript || activeInput?.isTypeless == true {
            pendingEnter = true
            Log.key("回车排队，等待转写落地")
            return
        }
        KeyTap.tap(settings.current.send)
    }

    /// True when the device runs an older build than the latest release.
    var firmwareUpdateAvailable: Bool {
        guard let latest = updater.latest, firmwareVersion != "—", !firmwareVersion.isEmpty
        else { return false }
        return versionIsNewer(latest.version, than: ReleaseInfo.version(fromTag: firmwareVersion))
    }

    /// Downloads the firmware from the current release and streams it to the
    /// device. Recording is refused while this runs.
    func upgradeFirmware() {
        guard !otaRunning else { return }
        otaRunning = true
        otaProgress = 0
        otaNote = "正在下载固件…"
        updater.downloadFirmware { [weak self] data, error in
            guard let self else { return }
            guard let data else {
                self.otaRunning = false
                self.otaNote = error ?? "下载失败"
                return
            }
            self.otaNote = "正在推送 \(data.count / 1024) KB 到设备…"
            Log.sys(self.otaNote)
            self.ble.sendFirmware(data)
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
        if appliedButtons != settings.current.buttons {
            appliedButtons = settings.current.buttons
            ble.writeActions(settings.current.buttons.actionCodes)
        }
        if appliedPowerMode != settings.current.powerMode {
            appliedPowerMode = settings.current.powerMode
            ble.setPowerMode(settings.current.powerMode)
            Log.sys("设备功耗模式：\(settings.current.powerMode.title)")
        }

        bleSnap = ble.snapshot
        audioPeak = audio.peak
        if Date().timeIntervalSince(lastEnvCheck) >= Self.envCheckSec {
            lastEnvCheck = Date()
            refreshChecks()
        }
        if mic.result != "未测试" { audioTestNote = mic.result }

        let interval = max(0.5, settings.current.typelessPollSec)
        // 录音中和等待转写落地时都要快轮询：停止后设备停在 PROCESSING 相位，
        // 要等我们把 Typeless 的空闲状态写回去才会放行排队的回车。慢轮询会白白
        // 吃掉设备端的超时预算，让回车抢在文字之前落下。
        let hot = bleSnap.streaming || awaitingTranscript
        if hot || Date().timeIntervalSince(lastTypelessPoll) >= interval {
            lastTypelessPoll = Date()
            let st = typeless.poll()
            if st != typelessState {
                Log.typeless(st.title)
                typelessState = st
            }
            if st == .idle || st == .down {
                awaitingTranscript = false
                if pendingEnter {
                    pendingEnter = false
                    Log.key("转写完成，补发回车")
                    KeyTap.tap(settings.current.send)
                }
            }
            if activeInput?.isTypeless == true && !bleSnap.streaming && st == .idle {
                setActiveInput(nil)
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


/// Identifies one cell of the bindings grid, so the recorder sheet knows where
/// to write the shortcut it captures.
struct GestureSlot: Identifiable, Equatable {
    let key: ButtonKey
    let gesture: ButtonGesture
    var id: String { "\(key.rawValue).\(gesture.rawValue)" }
    var title: String { "\(key.title)\(gesture.title)" }
}
