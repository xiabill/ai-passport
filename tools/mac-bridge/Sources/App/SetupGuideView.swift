import AppKit
import SwiftUI

struct SetupGuideView: View {
    @ObservedObject var model: AppModel
    var compactWhenReady = false

    private var steps: [SetupStep] {
        [
            SetupStep(
                id: "accessibility",
                title: "辅助功能",
                detail: model.axOK ? "已授权，可模拟 Fn / F19 / 回车" : "打开设置后，在列表中打开 FoloVibe Bridge",
                symbol: "hand.tap.fill",
                tint: .blue,
                ok: model.axOK,
                actionTitle: model.axOK ? nil : "打开设置"),
            SetupStep(
                id: "bluetooth",
                title: "蓝牙",
                detail: model.bleSnap.bluetoothOn ? "蓝牙已开启" : "打开蓝牙，允许 Bridge 连接 Passport",
                symbol: "dot.radiowaves.left.and.right",
                tint: .cyan,
                ok: model.bleSnap.bluetoothOn,
                actionTitle: model.bleSnap.bluetoothOn ? nil : "打开设置"),
            SetupStep(
                id: "device",
                title: "Passport 设备",
                detail: model.bleSnap.subscribed ? model.bleSnap.deviceName : "打开设备并靠近 Mac，等待自动连接",
                symbol: "antenna.radiowaves.left.and.right",
                tint: .green,
                ok: model.bleSnap.subscribed,
                actionTitle: model.bleSnap.subscribed ? nil : "重新连接"),
            SetupStep(
                id: "audio",
                title: "虚拟音频设备",
                detail: model.blackholeOK
                    ? "正在使用 \(model.settings.current.outputDevice)"
                    : audioHint,
                symbol: "waveform",
                tint: .purple,
                ok: model.blackholeOK,
                actionTitle: model.blackholeOK ? nil : "一键配置"),
            SetupStep(
                id: "typeless",
                title: "Typeless",
                detail: model.typeless.running ? "应用正在运行" : "打开 Typeless 后才能接收语音",
                symbol: "mic.fill",
                tint: .orange,
                ok: model.typeless.running,
                actionTitle: model.typeless.running ? nil : "打开 Typeless"),
            SetupStep(
                id: "microphone",
                title: "Typeless 麦克风",
                detail: model.typelessMicOK
                    ? "已对齐 \(model.typelessMicLabel)"
                    : micHint,
                symbol: "slider.horizontal.3",
                tint: .pink,
                ok: model.typelessMicOK,
                actionTitle: model.typelessMicOK ? nil : "一键配置"),
        ]
    }

    /// Reports what is actually available so a first-time user is not told to
    /// install BlackHole when a working loopback device is already present.
    private var audioHint: String {
        let usable = model.usableLoopbacks
        if !usable.isEmpty { return "点“一键配置”使用 \(usable.joined(separator: "、"))" }
        let loopbacks = AudioOutput.loopbackDeviceNames()
        if loopbacks.isEmpty { return "尚未安装虚拟音频设备，点“一键配置”前往安装 BlackHole" }
        return "系统有 \(loopbacks.joined(separator: "、"))，但 Typeless 枚举不到，请重启 Typeless"
    }

    private var micHint: String {
        let usable = model.usableLoopbacks
        if usable.isEmpty { return "先完成上一步的虚拟音频设备配置" }
        return "点“一键配置”，自动把 Typeless 的语音输入设为 \(usable.first ?? "")"
    }

    var body: some View {
        SurfaceCard(
            compactWhenReady && steps.allSatisfy({ $0.ok }) ? "系统已准备好" : "首次设置向导",
            subtitle: compactWhenReady && steps.allSatisfy({ $0.ok })
                ? "关键权限、音频和设备连接均已通过检查"
                : "按顺序完成授权和音频设置；从系统设置回来后点“再次检查”") {
            if compactWhenReady && steps.allSatisfy({ $0.ok }) {
                readySummary
            } else {
                fullGuide
            }
        }
    }

    private var fullGuide: some View {
        let pending = steps.filter { !$0.ok }
        let done = steps.filter { $0.ok }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ProgressView(value: Double(done.count), total: Double(steps.count))
                    .tint(pending.isEmpty ? .green : .accentColor)
                Text("\(done.count)/\(steps.count) 已完成")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(pending.isEmpty ? .green : .primary)
                    .monospacedDigit()
                    .fixedSize()
                Spacer(minLength: 8)
                Button { model.repairSetup() } label: {
                    Label("自动修复", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                Button { model.refreshChecks() } label: {
                    Label("再次检查", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            // 只展开还没做完的步骤。已完成的六行会把首屏整个吃掉，而向导要
            // 回答的问题只有一个：接下来还要做什么。
            if !pending.isEmpty {
                VStack(spacing: 0) {
                    ForEach(pending) { step in
                        stepRow(step)
                        if step.id != pending.last?.id { Divider().padding(.leading, 42) }
                    }
                }
            }

            if !done.isEmpty {
                Label(
                    "已通过：" + done.map(\.title).joined(separator: "、"),
                    systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if pending.isEmpty {
                Label("设置完成，可以直接使用硬件按键。", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            } else if !model.repairNote.isEmpty {
                Label(model.repairNote, systemImage: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var readySummary: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.green)
                .frame(width: 42, height: 42)
                .background(Color.green.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("全部准备完成")
                    .font(.callout.weight(.semibold))
                Text("硬件按键、蓝牙、音频和 Typeless 都可以使用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button { model.refreshChecks() } label: {
                Label("再次检查", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private func stepRow(_ step: SetupStep) -> some View {
        HStack(spacing: 12) {
            Image(systemName: step.symbol)
                .foregroundStyle(step.ok ? .green : step.tint)
                .frame(width: 30, height: 30)
                .background((step.ok ? Color.green : step.tint).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title).font(.callout.weight(.semibold))
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 10)
            if let actionTitle = step.actionTitle {
                Button(actionTitle) { perform(step) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }
        }
        .padding(.vertical, 6)
    }

    private func perform(_ step: SetupStep) {
        switch step.id {
        case "accessibility":
            Permissions.openAccessibility()
            KeyTap.promptTrust()
        case "bluetooth":
            Permissions.openBluetooth()
        case "device":
            model.ble.reconnect()
        case "audio", "microphone":
            model.autoPairAudio()
        case "typeless":
            if !Permissions.openTypeless() {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
            }
        default:
            break
        }
    }
}

private struct SetupStep: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let ok: Bool
    let actionTitle: String?
}
