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
                    subtitle: "给每个手势配一个动作和一个快捷键",
                    trailing: AnyView(
                        Button { store.reset() } label: {
                            Label("恢复默认", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered))
                )

                SetupGuideView(model: model)

                ForEach(ButtonKey.allCases, id: \.self) { key in
                    SurfaceCard(key.title, subtitle: keySummary(key)) {
                        VStack(spacing: 10) {
                            ForEach(ButtonGesture.allCases, id: \.self) { gesture in
                                gestureRow(key, gesture)
                                if gesture != ButtonGesture.allCases.last { Divider() }
                            }
                        }
                    }
                }

                SurfaceCard("连接设备", subtitle: "空闲的设备会自动连上；另一台 Mac 在用的，点「使用」切到本机") {
                    VStack(spacing: 15) {
                        deviceList
                        Divider()
                        SettingRow("设备名前缀", subtitle: "默认 FoloVibe，填完整名字可只连某一台") {
                            TextField("FoloVibe", text: prefixBinding)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                        }
                        SettingRow("音频输出设备", subtitle: "设备的声音送进这个虚拟麦克风，语音软件从这里听") {
                            HStack(spacing: 8) {
                                Picker("输出设备", selection: outputBinding) {
                                    ForEach(audioDeviceOptions, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                                .frame(width: 220)
                                Button { model.refreshChecks() } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .help("刷新音频设备列表")
                            }
                        }
                        if !model.audioOK {
                            HStack(spacing: 8) {
                                Label("未找到这个音频设备", systemImage: "exclamationmark.triangle.fill")
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
                    }
                }

                SurfaceCard("设备功耗模式", subtitle: "根据你是否长时间闲置，切换设备的耗电策略") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("", selection: powerModeBinding) {
                            ForEach(BridgePowerMode.allCases, id: \.self) { mode in
                                Label(mode.title, systemImage: mode.symbol).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(store.current.powerMode.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

                SurfaceCard("启动与权限", subtitle: "这些选项只影响本程序") {
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

                SurfaceCard("运行日志", subtitle: "出问题时看这里") {
                    DisclosureGroup("展开日志") {
                        LogView(model: model).frame(height: 260)
                    }
                    .font(.callout)
                }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .sheet(item: $model.strokeTarget) { slot in
            StrokeCaptureSheet(
                title: slot.title,
                current: store.current.buttons.stroke(slot.key, slot.gesture)
            ) { stroke in
                store.current.buttons.setStroke(slot.key, slot.gesture, stroke)
            }
        }
    }

    /// One gesture on one button: what it does, which key it sends, and what
    /// the device screen calls it. One line, so a button reads top to bottom.
    @ViewBuilder
    private func gestureRow(_ key: ButtonKey, _ gesture: ButtonGesture) -> some View {
        let action = store.current.buttons.action(key, gesture)
        let stroke = store.current.buttons.stroke(key, gesture)
        HStack(spacing: 10) {
            Text(gesture.title)
                .font(.callout.weight(.medium))
                .frame(width: 42, alignment: .leading)

            Menu {
                Button("无") { bind(key, gesture, .none) }
                Divider()
                Button("语音输入（同时开始录音）") { bind(key, gesture, .voice) }
                Button("全选并删除") { bind(key, gesture, .clear) }
                Button("交给另一台 Mac") { bind(key, gesture, .handoff) }
                Divider()
                ForEach(KeyPreset.Group.allCases, id: \.self) { group in
                    Menu(group.rawValue) {
                        ForEach(KeyPreset.grouped(group)) { preset in
                            Button("\(preset.title)   \(preset.stroke.label)") {
                                store.current.buttons.bind(key, gesture, preset: preset.id)
                            }
                        }
                    }
                }
                Divider()
                Button("自定义按键…") {
                    bind(key, gesture, .key)
                    model.strokeTarget = GestureSlot(key: key, gesture: gesture)
                }
            } label: {
                Text(menuTitle(key, gesture))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 190)

            // The key itself, clickable when there is one to change.
            if action.needsStroke {
                Button {
                    model.strokeTarget = GestureSlot(key: key, gesture: gesture)
                } label: {
                    Text(stroke?.display ?? "未设置")
                        .font(.caption.monospaced())
                        .frame(width: 104)
                }
                .controlSize(.small)
                .help("点一下重新录制，可选按一下、连按两下或按住")
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 104)
            }

            TextField(action.deviceTitle, text: labelBinding(key, gesture))
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .controlSize(.small)
                .frame(width: 92)
                .help("设备屏幕上显示的名字，留空用默认")
        }
    }

    /// What the menu shows now: the preset's name when it is one, otherwise
    /// the action.
    private func menuTitle(_ key: ButtonKey, _ gesture: ButtonGesture) -> String {
        let action = store.current.buttons.action(key, gesture)
        guard action == .key else { return action.title }
        if let stroke = store.current.buttons.stroke(key, gesture),
            let preset = KeyPreset.all.first(where: {
                $0.stroke.keyCode == stroke.keyCode && $0.stroke.modifiers == stroke.modifiers
                    && $0.stroke.isMedia == stroke.isMedia
            })
        {
            return preset.title
        }
        return "自定义按键"
    }

    /// A one-line summary under the button's name, so the card says what the
    /// button does without being unfolded.
    private func keySummary(_ key: ButtonKey) -> String {
        ButtonGesture.allCases.map { gesture -> String in
            let action = store.current.buttons.action(key, gesture)
            if action == .none { return "\(gesture.title) —" }
            let name = store.current.buttons.label(key, gesture)
                ?? (action == .key ? menuTitle(key, gesture) : action.title)
            return "\(gesture.title) \(name)"
        }.joined(separator: "   ")
    }

    private func bind(_ key: ButtonKey, _ gesture: ButtonGesture, _ action: ButtonAction) {
        store.current.buttons.set(key, gesture, action)
        if !action.needsStroke { store.current.buttons.setStroke(key, gesture, nil) }
        store.current.buttons.setLabel(key, gesture, nil)
    }

    @ViewBuilder
    private var deviceList: some View {
        let devices = model.bleSnap.devices
        if devices.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在寻找附近的 Passport…").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            VStack(spacing: 10) {
                ForEach(devices, id: \.id) { d in
                    HStack(spacing: 12) {
                        Image(systemName: d.ready ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(d.ready ? .green : .secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name).font(.callout.weight(.medium))
                            Text(deviceDetail(d)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if d.ready {
                            Text("使用中").font(.caption).foregroundStyle(.green)
                        } else if d.connected {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("使用") { model.useDevice(d) }
                                .buttonStyle(.bordered)
                                .help(d.busyElsewhere
                                    ? "它正在另一台 Mac 上使用，点这里会切换到本机"
                                    : "连接这台设备")
                        }
                    }
                }
            }
        }
    }

    private func deviceDetail(_ d: BLEClient.Device) -> String {
        var parts: [String] = []
        if d.ready {
            parts.append("已连接本机")
        } else if d.connected {
            parts.append("连接中")
        } else if d.busyElsewhere {
            parts.append("另一台 Mac 在用")
        } else {
            parts.append("空闲")
        }
        if let rssi = d.rssi { parts.append("信号 \(rssi)") }
        if !d.firmwareVersion.isEmpty { parts.append(d.firmwareVersion) }
        return parts.joined(separator: " · ")
    }

    private func labelBinding(_ key: ButtonKey, _ gesture: ButtonGesture) -> Binding<String> {
        Binding(
            get: { store.current.buttons.label(key, gesture) ?? "" },
            set: { store.current.buttons.setLabel(key, gesture, $0) })
    }

    private func actionBinding(_ key: ButtonKey, _ gesture: ButtonGesture) -> Binding<ButtonAction> {
        Binding(
            get: { store.current.buttons.action(key, gesture) },
            set: { store.current.buttons.set(key, gesture, $0) })
    }

    private var prefixBinding: Binding<String> {
        Binding(get: { store.current.devicePrefix }, set: { store.current.devicePrefix = $0 })
    }

    private var outputBinding: Binding<String> {
        Binding(get: { store.current.outputDevice }, set: { store.current.outputDevice = $0 })
    }

    private var audioDeviceOptions: [String] {
        var names = model.audioDeviceNames
        if !names.contains(store.current.outputDevice) {
            names.insert(store.current.outputDevice, at: 0)
        }
        return names
    }

    private var autoReconnect: Binding<Bool> {
        Binding(get: { store.current.autoReconnect }, set: { store.current.autoReconnect = $0 })
    }

    private var powerModeBinding: Binding<BridgePowerMode> {
        Binding(get: { store.current.powerMode }, set: { store.current.powerMode = $0 })
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
}
