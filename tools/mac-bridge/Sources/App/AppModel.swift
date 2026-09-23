import AppKit
import Combine
import FoloVibeCore
import Foundation

enum AppTab: String, CaseIterable, Hashable {
    case keys = "按键"
    case devices = "设备"
    case general = "通用"

    var title: String { rawValue }

    var subtitle: String {
        switch self {
        case .keys: return "三个按钮各自的单击、双击、长按"
        case .devices: return "连接、音频、功耗和固件"
        case .general: return "程序更新、启动方式和日志"
        }
    }

    var symbol: String {
        switch self {
        case .keys: return "button.programmable"
        case .devices: return "antenna.radiowaves.left.and.right"
        case .general: return "gearshape"
        }
    }
}

/// One cell of the button grid, identified for the shortcut recorder sheet.
struct GestureSlot: Identifiable, Hashable {
    let key: ButtonKey
    let gesture: ButtonGesture
    var id: String { "\(key.rawValue).\(gesture.rawValue)" }
    var title: String { "\(key.title)\(gesture.title)" }
}

final class AppModel: ObservableObject {
    static let shared = AppModel()

    let settings = SettingsStore()
    let audio = AudioOutput()
    let mic = MicTest()
    let logFilter = LogFilter()
    let updater = Updater()
    private(set) var ble: BLEClient!

    @Published var tab: AppTab = .keys
    @Published var bleSnap = BLEClient.Snapshot()
    @Published var audioPeak: Int = 0
    @Published var axOK = false
    @Published var audioOK = false
    @Published var loginOn = false
    @Published var lastAction = "—"
    /// A device changing hands, worth a line on screen for a short while.
    @Published var handoffNotice = ""
    /// Set when a take found nothing listening to the virtual device, which
    /// is what quietly broke dictation for a long time. Empty when fine.
    @Published var listenerWarning = ""
    /// Who was listening on the last take, for the status line.
    @Published var listenerApps = ""
    /// The grid cell whose gesture just fired, lit briefly in settings.
    @Published var firedSlot: GestureSlot?
    /// Which grid slot is currently recording a shortcut.
    @Published var strokeTarget: GestureSlot?
    @Published var firmwareVersion = "—"
    @Published var otaProgress: Double = 0
    @Published var otaNote = ""
    @Published var otaRunning = false
    @Published var audioDeviceNames: [String] = []
    @Published var audioTestNote = "尚未测试"
    @Published var repairNote = ""

    private var lastOutput = ""
    private var lastEnvCheck = Date.distantPast
    /// refreshChecks() enumerates every CoreAudio device, far too costly for
    /// the 0.5 s UI tick.
    private static let envCheckSec: TimeInterval = 5
    private var appliedPowerMode: BridgePowerMode?
    private var appliedButtons = ButtonMap.default
    private var wasStreaming = false
    private var listenerCheckAt: Date?

    private init() {}

    func start() {
        ble = BLEClient(audio: audio, mic: mic)
        ble.prefix = settings.current.devicePrefix
        ble.autoReconnect = settings.current.autoReconnect
        ble.setPowerMode(settings.current.powerMode)
        appliedPowerMode = settings.current.powerMode
        ble.onGesture = { [weak self] g, device in self?.handleGesture(g, from: device) }
        ble.onFirmwareVersion = { [weak self] v in self?.firmwareVersion = v }
        ble.onHandedOver = { [weak self] name in self?.notice("\(name) 已被另一台 Mac 接管") }
        ble.onTookOver = { [weak self] name in self?.notice("已从另一台 Mac 接管 \(name)") }
        ble.onOTAProgress = { [weak self] p in self?.otaProgress = p }
        ble.onOTAFinished = { [weak self] err in
            guard let self else { return }
            self.otaRunning = false
            self.otaNote = err ?? "固件已发送，设备正在校验并重启"
            Log.sys(self.otaNote)
        }
        ble.writeActions(settings.current.buttons.actionCodes)
        ble.writeLabels(renderedLabels())
        applyAudio()
        refreshChecks()
        // Quiet check on launch; the settings page shows the result.
        updater.check(quiet: true)
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        Log.sys("FoloVibe 已启动")
    }

    /// Everything the setup guide checks is in place, so it can step aside.
    var setupComplete: Bool {
        axOK && bleSnap.bluetoothOn && bleSnap.subscribed && audioOK
    }

    /// Refresh permission and device checks after the user returns from a
    /// system settings page.
    func refreshChecks() {
        let wasAXOK = axOK
        axOK = KeyTap.trusted
        audioDeviceNames = AudioOutput.outputDeviceNames()
        audioOK = AudioOutput.deviceExists(settings.current.outputDevice)
        loginOn = LoginItem.enabled
        if wasAXOK != axOK {
            Log.sys(axOK ? "辅助功能已授权，可以发送快捷键" : "辅助功能未开，按键发不出去")
        }
    }

    /// Fixes the first blocking item and stops, so the user can see the result
    /// before the next one. Permissions stay explicit; only safe local repairs
    /// happen on their own.
    func repairSetup() {
        refreshChecks()
        bleSnap = ble.snapshot
        if !axOK {
            Permissions.openAccessibility()
            KeyTap.promptTrust()
            repairNote = "已打开辅助功能设置：请勾选 FoloVibe Bridge，再点“再次检查”。"
            return
        }
        if !bleSnap.bluetoothOn {
            Permissions.openBluetooth()
            repairNote = "已打开蓝牙设置；开启后点“再次检查”。"
            return
        }
        if !bleSnap.subscribed {
            ble.reconnect()
            repairNote = "已重新扫描设备；请保持设备开机并靠近 Mac。"
            return
        }
        if !audioOK {
            if let pick = AudioOutput.loopbackDeviceNames().first {
                settings.current.outputDevice = pick
                applyAudio()
                repairNote = "已把音频输出设为 \(pick)。请在语音软件里把麦克风也选成它。"
            } else {
                Permissions.openBlackHoleDownload()
                repairNote = "没有找到虚拟麦克风，已打开 BlackHole 安装页；装完点“再次检查”。"
            }
            refreshChecks()
            return
        }
        repairNote = "检查完成，没有发现需要修复的项目。"
    }

    func applyAudio() {
        lastOutput = settings.current.outputDevice
        do {
            try audio.start(deviceNameContains: settings.current.outputDevice)
            audioOK = true
        } catch {
            audioOK = false
            Log.audio(error.localizedDescription)
        }
    }

    func playAudioTest() {
        guard audioOK else {
            audioTestNote = "无法测试：请先选择可用的音频输出设备。"
            return
        }
        audio.playTestTone()
        audioTestNote = "已播放 2 秒测试音；请确认语音软件有反应。"
    }

    func toggleMicTest() {
        if mic.isArmed {
            mic.cancel()
        } else {
            mic.arm()
        }
        audioTestNote = mic.result
    }

    func handleGesture(_ gesture: GestureEvent, from device: UUID? = nil) {
        let map = settings.current.buttons
        let action = map.action(gesture.key, gesture.gesture)
        let stroke = map.stroke(gesture.key, gesture.gesture)
        let shown = action.needsStroke ? (stroke?.display ?? "未录制快捷键") : action.title
        lastAction = action == .none ? "\(gesture.title)（未绑定）" : "\(gesture.title) → \(shown)"
        Log.key(lastAction)
        let slot = GestureSlot(key: gesture.key, gesture: gesture.gesture)
        firedSlot = slot
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.firedSlot == slot { self?.firedSlot = nil }
        }

        switch action {
        case .none:
            break
        case .handoff:
            // Only the device whose button was pressed moves; others stay.
            if let device { ble.release(device) }
        case .voice, .key:
            // Voice input and a plain shortcut send the same thing. The device
            // is what knows whether a press starts or ends a take, and it has
            // already armed or released its own microphone by the time this
            // arrives.
            guard let stroke else {
                Log.key("这个手势还没设按键，先在设置里选一个")
                return
            }
            KeyTap.send(stroke)
        case .clear:
            KeyTap.tapClearAll()
        }
    }

    /// Custom screen labels drawn here, by wire slot. Every slot is present so a
    /// label removed in settings is cleared on the device too.
    private func renderedLabels() -> [UInt8: Data?] {
        var out = [UInt8: Data?]()
        for key in ButtonKey.allCases {
            for gesture in ButtonGesture.allCases {
                let slot = ButtonMap.wireSlot(key, gesture)
                // updateValue, not subscript assignment: assigning a nil
                // Data? through the subscript deletes the key instead of
                // storing "no label", and the slot would never be cleared.
                out.updateValue(settings.current.buttons.screenName(key, gesture).map {
                    LabelRenderer.render($0, main: gesture == .click)
                }, forKey: slot)
            }
        }
        // Which Mac the device belongs to, for its status line. Drawn here for
        // the same reason as the labels: Mac names are rarely plain ASCII.
        out[VibeProtocol.labelHostSlot] = LabelRenderer.render(Self.macName, kind: .host)
        return out
    }

    /// Looks at who is recording while the device talks, and says so when
    /// nobody is listening to the virtual device.
    private func checkListeners() {
        guard let listeners = AudioListeners.current() else { return }
        let target = settings.current.outputDevice
        let hearing = listeners.filter { l in
            l.devices.contains { $0.localizedCaseInsensitiveContains(target) }
        }
        if !hearing.isEmpty {
            listenerWarning = ""
            listenerApps = hearing.map(\.app).joined(separator: "、")
            return
        }
        listenerApps = ""
        if listeners.isEmpty {
            listenerWarning = "说话时没有软件在录音：语音软件可能没有被唤起，检查这个手势录的快捷键"
        } else {
            let who = listeners.map { "\($0.app) 在听 \($0.devices.joined(separator: "、"))" }
            listenerWarning = who.joined(separator: "；") + "。没有软件在听 \(target)，"
                + "把语音软件的麦克风改成它"
        }
        Log.audio(listenerWarning)
    }

    /// The name the user gave this Mac, as shown in Sharing settings.
    static let macName: String = Host.current().localizedName ?? "这台 Mac"

    private func notice(_ text: String) {
        handoffNotice = text
        // Long enough to read on the way past, short enough not to linger.
        let shown = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            if self?.handoffNotice == shown { self?.handoffNotice = "" }
        }
    }

    /// Use a device now, taking it from another Mac if one has it.
    func useDevice(_ device: BLEClient.Device) {
        ble.use(device.id)
    }

    /// True when the device runs an older build than the latest release.
    var firmwareUpdateAvailable: Bool {
        guard let latest = updater.latest else { return false }
        return bleSnap.devices.contains {
            !$0.firmwareVersion.isEmpty
                && versionIsNewer(latest.version, than: ReleaseInfo.version(fromTag: $0.firmwareVersion))
        }
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
            ble.writeLabels(renderedLabels())
        }
        if appliedPowerMode != settings.current.powerMode {
            appliedPowerMode = settings.current.powerMode
            ble.setPowerMode(settings.current.powerMode)
            Log.sys("设备功耗模式：\(settings.current.powerMode.title)")
        }

        bleSnap = ble.snapshot
        audioPeak = audio.peak
        // A dictation app takes a moment to open its microphone after the
        // shortcut, so look a little after the take starts, not at once.
        if bleSnap.streaming && !wasStreaming { listenerCheckAt = Date().addingTimeInterval(2) }
        wasStreaming = bleSnap.streaming
        if let at = listenerCheckAt, Date() >= at {
            listenerCheckAt = nil
            if bleSnap.streaming { checkListeners() }
        }
        if Date().timeIntervalSince(lastEnvCheck) >= Self.envCheckSec {
            lastEnvCheck = Date()
            refreshChecks()
            // macOS moves an audio engine back to the default output on its own
            // after a configuration change. Catch it within seconds rather
            // than let the next take play out of the speakers.
            if !audio.isOnChosenDevice {
                Log.audio("输出漂离了 \(settings.current.outputDevice)，重新绑定")
                audio.rebuild(reason: "输出设备漂移")
            }
        }
        if mic.result != "未测试" { audioTestNote = mic.result }

    }
}

