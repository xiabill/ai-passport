import FoloVibeCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: SettingsStore
    @ObservedObject var updater: Updater

    init(model: AppModel) {
        self.model = model
        self.store = model.settings
        self.updater = model.updater
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(
                    title: "设置",
                    subtitle: "把硬件按键和两个输入法配置成你的工作流",
                    trailing: AnyView(
                        Button { store.reset() } label: {
                            Label("恢复默认", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered))
                )

                SetupGuideView(model: model)

                SurfaceCard("设备功耗模式", subtitle: "根据你是否长时间闲置，快速切换设备的耗电策略") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("功耗模式", selection: powerModeBinding) {
                            ForEach(BridgePowerMode.allCases, id: \.self) { mode in
                                Label(mode.title, systemImage: mode.symbol).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(store.current.powerMode.subtitle + "。省电模式下，设备闲置 60 秒后会暂停 BLE 广播，按普通功能键即可恢复。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SurfaceCard("连接设备", subtitle: "Bridge 会自动寻找名称以此前缀开头的 Passport") {
                    VStack(spacing: 15) {
                        SettingRow("设备名前缀", subtitle: "默认 FoloVibe") {
                            TextField("FoloVibe", text: prefixBinding)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                        }
                        SettingRow("音频输出设备", subtitle: "选择 Passport 音频要送入的虚拟设备") {
                            HStack(spacing: 8) {
                                Picker("输出设备", selection: outputBinding) {
                                    ForEach(audioDeviceOptions, id: \.self) { name in
                                        Text(name).tag(name)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 220)
                                Button { model.refreshChecks() } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .help("刷新音频设备列表")
                            }
                        }
                        if !model.blackholeOK {
                            HStack(spacing: 8) {
                                Label("未找到当前输出设备", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Button("安装 BlackHole") { Permissions.openBlackHoleDownload() }
                                Button("打开声音设置") { Permissions.openSound() }
                            }
                        }
                        Divider()
                        Toggle(isOn: autoReconnect) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("断开后自动重连").font(.callout.weight(.medium))
                                Text("设备重新出现时自动恢复连接").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        HStack(spacing: 10) {
                            Image(systemName: model.bleSnap.handoffPaused ? "pause.circle.fill" : "arrow.left.arrow.right.circle.fill")
                                .foregroundStyle(model.bleSnap.handoffPaused ? .orange : .blue)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("多 Mac 切换").font(.callout.weight(.medium))
                                Text(model.bleSnap.handoffPaused
                                    ? "本机已暂时让出设备，另一台 Mac 可以自动接管"
                                    : "同一设备一次连接一台 Mac，需要换电脑时先释放设备")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.bleSnap.handoffPaused {
                                Button("恢复自动连接") { model.ble.resumeAfterHandoff() }
                                    .buttonStyle(.bordered)
                            } else {
                                Button("释放给另一台 Mac") { model.ble.releaseForHandoff() }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }

                SurfaceCard("硬件按键", subtitle: "三个键 × 三个手势，改完立刻同步到设备") {
                    VStack(alignment: .leading, spacing: 9) {
                        // 一行一个键、一列一个手势:9 个绑定一屏看全，比按键分组
                        // 少占三分之二的高度。
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                            GridRow {
                                Text("").gridCellUnsizedAxes(.horizontal)
                                ForEach(ButtonGesture.allCases, id: \.self) { gesture in
                                    Text(gesture.title)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            ForEach(ButtonKey.allCases, id: \.self) { key in
                                GridRow {
                                    Text(key.title)
                                        .font(.callout.weight(.medium))
                                        .gridCellUnsizedAxes(.horizontal)
                                    ForEach(ButtonGesture.allCases, id: \.self) { gesture in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Picker("", selection: actionBinding(key, gesture)) {
                                                ForEach(ButtonAction.allCases, id: \.self) { action in
                                                    Text(action.title).tag(action)
                                                }
                                            }
                                            .labelsHidden()
                                            .pickerStyle(.menu)
                                            .frame(minWidth: 128)
                                            if store.current.buttons.action(key, gesture) == .customKey {
                                                Button {
                                                    model.strokeTarget = GestureSlot(key: key, gesture: gesture)
                                                } label: {
                                                    Text(store.current.buttons.stroke(key, gesture)?.label ?? "点击录制")
                                                        .font(.caption)
                                                        .frame(maxWidth: .infinity)
                                                }
                                                .controlSize(.small)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Text("设备屏幕显示每个键的单击动作。绑定存在 Bridge 里，换绑不用重刷固件。选“自定义按键”可以录制任意快捷键。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SurfaceCard("输入法快捷键", subtitle: "上面的动作最终按这里的键发给输入法") {
                    VStack(alignment: .leading, spacing: 14) {
                        keyRow("Typeless 基础键", "翻译自动加 Shift，随便问自动加 Space", talkBinding, Hotkey.talkKeys, .blue, "mic.fill", .talk)
                        keyRow("豆包快捷键", "豆包“免按模式”的按键，Bridge 会按它要求发双击", doubaoBinding, Hotkey.doubaoKeys, .green, "mic", .doubao)
                        keyRow("发送键", "“发送回车”动作使用的键", sendBinding, Hotkey.sendKeys, .accentColor, "return", .send)
                        Text("可以直接从列表选择，也可以点“录入”后按实体键。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SurfaceCard("Typeless 闭环", subtitle: "Bridge 会观察 Typeless 状态，在快捷键没有生效时自动补按") {
                    VStack(alignment: .leading, spacing: 15) {
                        Toggle(isOn: retapOn) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("启用自动补按").font(.callout.weight(.medium))
                                Text("只在检测到状态不一致时补按，不改变正常输入流程").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 12) {
                            valueField("开始等待", value: retapFrom, suffix: "秒")
                            valueField("结束等待", value: retapTo, suffix: "秒")
                            valueField("最多补按", value: retapMax, suffix: "次")
                        }
                        Divider()
                        SettingRow("状态轮询", subtitle: "读取 Typeless 最近状态的间隔") {
                            HStack(spacing: 6) {
                                TextField("2", value: poll, formatter: number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 72)
                                Text("秒").foregroundStyle(.secondary)
                            }
                        }
                        Label(
                            model.typelessMicOK ? "当前麦克风：\(model.typelessMicLabel)" : "当前麦克风不匹配：\(model.typelessMicLabel)",
                            systemImage: model.typelessMicOK ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(model.typelessMicOK ? .green : .orange)
                    }
                }

                SurfaceCard("软件更新", subtitle: "从 GitHub 获取最新版本") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text("当前版本 \(model.updater.currentVersion)")
                                .font(.callout.weight(.medium))
                            Spacer()
                            Button { model.updater.check() } label: {
                                Label("检查更新", systemImage: "arrow.clockwise")
                            }
                            .disabled(model.updater.busy)
                            if model.updater.updateAvailable {
                                Button { model.updater.installUpdate() } label: {
                                    Label("升级并重启", systemImage: "arrow.down.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.updater.busy)
                            }
                        }
                        Text(model.updater.status)
                            .font(.caption)
                            .foregroundStyle(model.updater.updateAvailable ? .orange : .secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()

                        // Firmware follows the app: upgrade the Mac side first,
                        // then let it push the matching image to the device.
                        HStack(spacing: 10) {
                            Text("设备固件 \(model.firmwareVersion)")
                                .font(.callout.weight(.medium))
                            Spacer()
                            if model.otaRunning {
                                ProgressView(value: model.otaProgress).frame(width: 120)
                                Text("\(Int(model.otaProgress * 100))%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            } else if model.firmwareUpdateAvailable {
                                Button { model.upgradeFirmware() } label: {
                                    Label("升级固件", systemImage: "cpu")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!model.bleSnap.subscribed)
                            }
                        }
                        if !model.otaNote.isEmpty {
                            Text(model.otaNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if model.firmwareUpdateAvailable && !model.bleSnap.subscribed {
                            Text("设备未连接，连上后才能升级固件")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                SurfaceCard("启动与权限", subtitle: "这些选项只影响 Bridge 自身，不会修改 Typeless 设置") {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: loginBinding) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("开机启动").font(.callout.weight(.medium))
                                Text("登录 macOS 后自动启动 Bridge").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Toggle(isOn: hidden) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("启动后只留菜单栏").font(.callout.weight(.medium))
                                Text("适合日常使用，仍可从菜单栏重新打开窗口").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        HStack(spacing: 10) {
                            Button("打开辅助功能") { Permissions.openAccessibility(); KeyTap.promptTrust() }
                            Button("打开蓝牙设置") { Permissions.openBluetooth() }
                            Button("再次检查") { model.refreshChecks() }
                        }
                    }
                }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .sheet(item: $model.strokeTarget) { slot in
            StrokeCaptureSheet(title: slot.title) { stroke in
                store.current.buttons.setStroke(slot.key, slot.gesture, stroke)
            }
        }
        .sheet(item: $model.captureTarget) { target in
            KeyCaptureSheet(title: target.title, keys: target.keys) { key in
                setKey(target, key)
            }
        }
    }

    private func actionBinding(_ key: ButtonKey, _ gesture: ButtonGesture) -> Binding<ButtonAction> {
        Binding(
            get: { store.current.buttons.action(key, gesture) },
            set: { store.current.buttons.set(key, gesture, $0) })
    }

    private func keyRow(
        _ title: String,
        _ subtitle: String,
        _ binding: Binding<String>,
        _ keys: [Hotkey],
        _ tint: Color,
        _ symbol: String,
        _ target: KeyCaptureTarget
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: binding) {
                ForEach(keys, id: \.name) { Text($0.name).tag($0.name) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 150, alignment: .trailing)
            Button("录入") { model.captureTarget = target }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("按下要映射的按键")
        }
    }

    private func valueField(_ label: String, value: Binding<Double>, suffix: String) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                TextField(label, value: value, formatter: number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 76)
            }
            Text(suffix).font(.caption).foregroundStyle(.secondary).padding(.top, 18)
        }
    }

    private func valueField(_ label: String, value: Binding<Int>, suffix: String) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                TextField(label, value: value, formatter: intNumber)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 76)
            }
            Text(suffix).font(.caption).foregroundStyle(.secondary).padding(.top, 18)
        }
    }

    private var number: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }
    private var intNumber: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .none
        return f
    }

    private var prefixBinding: Binding<String> {
        Binding(get: { store.current.devicePrefix }, set: { store.current.devicePrefix = $0 })
    }
    private var outputBinding: Binding<String> {
        Binding(get: { store.current.outputDevice }, set: { store.current.outputDevice = $0 })
    }
    private var audioDeviceOptions: [String] {
        var names = model.audioDeviceNames
        if !names.contains(store.current.outputDevice) { names.insert(store.current.outputDevice, at: 0) }
        return names.isEmpty ? [store.current.outputDevice] : names
    }
    private var autoReconnect: Binding<Bool> {
        Binding(get: { store.current.autoReconnect }, set: { store.current.autoReconnect = $0 })
    }
    private var powerModeBinding: Binding<BridgePowerMode> {
        Binding(get: { store.current.powerMode }, set: { store.current.powerMode = $0 })
    }
    private var talkBinding: Binding<String> {
        Binding(get: { store.current.talkKey }, set: { store.current.talkKey = $0 })
    }
    private var sendBinding: Binding<String> {
        Binding(get: { store.current.sendKey }, set: { store.current.sendKey = $0 })
    }
    private var doubaoBinding: Binding<String> {
        Binding(get: { store.current.doubaoKey }, set: { store.current.doubaoKey = $0 })
    }
    private var retapOn: Binding<Bool> {
        Binding(get: { store.current.retapEnabled }, set: { store.current.retapEnabled = $0 })
    }
    private var retapFrom: Binding<Double> {
        Binding(get: { store.current.retapFromSec }, set: { store.current.retapFromSec = $0 })
    }
    private var retapTo: Binding<Double> {
        Binding(get: { store.current.retapToSec }, set: { store.current.retapToSec = $0 })
    }
    private var retapMax: Binding<Int> {
        Binding(get: { store.current.retapMax }, set: { store.current.retapMax = $0 })
    }
    private var poll: Binding<Double> {
        Binding(get: { store.current.typelessPollSec }, set: { store.current.typelessPollSec = $0 })
    }
    private var hidden: Binding<Bool> {
        Binding(get: { store.current.startHidden }, set: { store.current.startHidden = $0 })
    }
    private var loginBinding: Binding<Bool> {
        Binding(
            get: { model.loginOn },
            set: {
                LoginItem.set($0)
                store.current.launchAtLogin = $0
            })
    }

    private func setKey(_ target: KeyCaptureTarget, _ key: Hotkey) {
        switch target {
        case .talk: store.current.talkKey = key.name
        case .doubao: store.current.doubaoKey = key.name
        case .send: store.current.sendKey = key.name
        }
    }
}

enum KeyCaptureTarget: String, Identifiable {
    case talk, doubao, send

    var id: String { rawValue }

    var title: String {
        switch self {
        case .talk: return "Typeless 基础键"
        case .doubao: return "豆包快捷键"
        case .send: return "发送键"
        }
    }

    var keys: [Hotkey] {
        switch self {
        case .talk: return Hotkey.talkKeys
        case .doubao: return Hotkey.doubaoKeys
        case .send: return Hotkey.sendKeys
        }
    }
}
