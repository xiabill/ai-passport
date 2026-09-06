import FoloVibeCore
import SwiftUI

struct StatusView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(
                    title: "状态总览",
                    subtitle: "硬件、音频和输入法都在这里快速确认",
                    trailing: AnyView(
                        HStack(spacing: 9) {
                            StatusPill(title: connectionTitle, color: connectionColor, symbol: connectionSymbol)
                            Button { model.ble.reconnect() } label: {
                                Label("重连", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderedProminent)
                            Menu {
                                if model.bleSnap.handoffPaused {
                                    Button("恢复自动连接") { model.ble.resumeAfterHandoff() }
                                } else {
                                    Button("切换 Mac") { model.ble.releaseForHandoff() }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .help("更多设备连接操作")
                        }))

                SetupGuideView(model: model, compactWhenReady: true)
                connectionCard

                // 自适应列：宽窗口并排两列以缩短页面，窄窗口自动退成单列，
                // 卡片内部因此永远拿得到足够宽度，不会被压出错位换行。
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 330), spacing: 12, alignment: .top)],
                    alignment: .leading, spacing: 12
                ) {
                    healthCard
                    audioCard
                    powerModeCard
                    audioTestCard
                }

                quickActions

                if !issueList.isEmpty { issuesCard }
            }
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var connectionCard: some View {
        SurfaceCard {
            HStack(spacing: 16) {
                Image(systemName: connectionSymbol)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(connectionColor)
                    .frame(width: 56, height: 56)
                    .background(connectionColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text(connectionTitle).font(.title3.weight(.semibold))
                    Text(model.bleSnap.deviceName == "—" ? "正在寻找 FoloVibe 设备" : model.bleSnap.deviceName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(model.bleSnap.phase).font(.callout.weight(.medium))
                    Text(model.bleSnap.rssi.map { "RSSI \($0) dBm" } ?? "RSSI —")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 10)], spacing: 10) {
                MetricTile(label: "蓝牙", value: model.bleSnap.bluetoothOn ? "已开启" : "未开启", symbol: "dot.radiowaves.left.and.right", tint: model.bleSnap.bluetoothOn ? .green : .orange)
                MetricTile(label: "服务", value: model.bleSnap.subscribed ? "已订阅" : "等待中", symbol: "antenna.radiowaves.left.and.right", tint: model.bleSnap.subscribed ? .green : .orange)
                MetricTile(label: "MTU", value: "\(model.bleSnap.mtu)", symbol: "arrow.left.arrow.right", tint: .blue)
            }
        }
    }

    private var quickActions: some View {
        SurfaceCard("硬件操作", subtitle: "按键会自动触发对应输入法，下面是当前映射") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                action(title: "语音输入", detail: "单击中键", shortcut: model.settings.current.talkKey, symbol: "mic.fill", tint: .blue)
                action(title: "翻译", detail: "双击中键", shortcut: "\(model.settings.current.talkKey) + Shift", symbol: "character.bubble", tint: .purple)
                action(title: "随便问", detail: "长按中键", shortcut: "\(model.settings.current.talkKey) + Space", symbol: "sparkles", tint: .orange)
            }
        }
    }

    private var powerModeCard: some View {
        SurfaceCard("设备功耗模式", subtitle: model.settings.current.powerMode.subtitle) {
            ViewThatFits(in: .horizontal) {
                powerModeRow(vertical: false)
                powerModeRow(vertical: true)
            }
        }
    }

    private func powerModeRow(vertical: Bool) -> some View {
        let layout: AnyLayout = vertical
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 14))
        return layout {
            HStack(spacing: 14) {
                Image(systemName: model.settings.current.powerMode.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(model.settings.current.powerMode == .eco ? .green : .orange)
                    .frame(width: 42, height: 42)
                    .background(
                        (model.settings.current.powerMode == .eco ? Color.green : Color.orange)
                            .opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.settings.current.powerMode.title)
                        .font(.callout.weight(.semibold))
                    Text("切换后会在下次 BLE 同步时立即应用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Picker("功耗模式", selection: powerModeBinding) {
                ForEach(BridgePowerMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 220)
        }
    }

    private func action(title: String, detail: String, shortcut: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ShortcutChip(text: shortcut)
        }
    }

    private var healthCard: some View {
        SurfaceCard("运行检查", subtitle: "输入前建议全部显示为正常") {
            VStack(alignment: .leading, spacing: 13) {
                CheckRow(title: "辅助功能", detail: model.axOK ? "可以发送快捷键" : "需要在系统设置中授权", ok: model.axOK)
                CheckRow(title: "虚拟音频设备", detail: model.blackholeOK ? model.settings.current.outputDevice : "未找到配置的输出设备", ok: model.blackholeOK)
                CheckRow(title: "Typeless", detail: model.typeless.running ? "应用正在运行" : "请先打开 Typeless", ok: model.typeless.running)
                CheckRow(title: "Typeless 麦克风", detail: model.typelessMicOK ? model.typelessMicLabel : "需要选择正确的音频设备", ok: model.typelessMicOK)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var audioCard: some View {
        SurfaceCard("音频活动", subtitle: "来自 Passport 的实时音频") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.bleSnap.streaming ? "正在输入" : "等待输入")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("峰值 \(model.audioPeak)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                WaveformMeter(level: CGFloat(model.audioPeak) / 32767, active: model.bleSnap.streaming)
                HStack {
                    Text("音频包 \(model.bleSnap.packets)")
                    Spacer()
                    Text("丢包 \(model.bleSnap.lost)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var audioTestCard: some View {
        SurfaceCard("声音效果测试", subtitle: "按顺序验证设备麦克风 → BLE → Bridge → 虚拟音频设备") {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    audioTestButtons(vertical: false)
                    audioTestButtons(vertical: true)
                }
                Text(model.audioTestNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 18) {
                    Label(model.blackholeOK ? "输出设备可用" : "输出设备缺失", systemImage: model.blackholeOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                    Label(model.bleSnap.packets > 0 ? "收到 BLE 音频包" : "等待 BLE 音频包", systemImage: model.bleSnap.packets > 0 ? "checkmark.circle.fill" : "hourglass")
                    Text("丢包 \(model.bleSnap.lost)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func audioTestButtons(vertical: Bool) -> some View {
        let layout: AnyLayout = vertical
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Button { model.playAudioTest() } label: {
                Label("播放测试音", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(.borderedProminent)
            Button { model.toggleMicTest() } label: {
                Label(
                    model.mic.isArmed ? "取消录音测试" : "录一段设备麦克风",
                    systemImage: model.mic.isArmed ? "stop.circle" : "record.circle")
            }
            Button { model.refreshChecks() } label: {
                Label("刷新链路", systemImage: "arrow.clockwise")
            }
        }
    }

    private var issuesCard: some View {
        SurfaceCard("需要处理", subtitle: "按顺序完成这些项目即可恢复完整功能") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(issueList, id: \.self) { issue in
                    Label(issue, systemImage: "arrow.right.circle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var issueList: [String] {
        var out = [String]()
        if !model.bleSnap.bluetoothOn { out.append("打开系统蓝牙") }
        if !model.bleSnap.subscribed { out.append("等待 Passport 广播 FoloVibe-* 并靠近 Mac") }
        if !model.axOK { out.append("在系统设置里给 FoloVibe Bridge 打开辅助功能") }
        if !model.blackholeOK {
            out.append("未找到 \(model.settings.current.outputDevice)，用状态页的“一键配置”自动挑一个可用设备")
        }
        if !model.typeless.running { out.append("打开 Typeless") }
        if model.typeless.running && !model.typelessMicOK {
            out.append("把 Typeless 麦克风改成 \(model.settings.current.outputDevice)，或用“一键配置”自动写入")
        }
        return out
    }

    private var connectionTitle: String {
        if model.bleSnap.streaming { return "正在输入" }
        if model.bleSnap.subscribed { return "设备已就绪" }
        if model.bleSnap.connected { return "正在连接" }
        return model.bleSnap.phase
    }

    private var connectionColor: Color {
        if model.bleSnap.streaming { return .red }
        if model.bleSnap.subscribed { return .green }
        if model.bleSnap.connected { return .orange }
        return .secondary
    }

    private var connectionSymbol: String {
        if model.bleSnap.streaming { return "waveform.and.mic" }
        if model.bleSnap.subscribed { return "checkmark.circle.fill" }
        if model.bleSnap.connected { return "arrow.triangle.2.circlepath" }
        return "dot.radiowaves.left.and.right"
    }

    private var powerModeBinding: Binding<BridgePowerMode> {
        Binding(
            get: { model.settings.current.powerMode },
            set: { model.settings.current.powerMode = $0 })
    }
}
