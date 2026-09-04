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
                title: "BlackHole 音频",
                detail: model.blackholeOK ? "输出设备可用：\(model.settings.current.outputDevice)" : "在声音设置确认已安装并启用 BlackHole 2ch",
                symbol: "waveform",
                tint: .purple,
                ok: model.blackholeOK,
                actionTitle: model.blackholeOK ? nil : "打开声音设置"),
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
                detail: model.typelessMicOK ? "已选择 \(model.typelessMicLabel)" : "打开 Typeless 设置 → 语音输入，选择 \(model.settings.current.outputDevice)",
                symbol: "slider.horizontal.3",
                tint: .pink,
                ok: model.typelessMicOK,
                actionTitle: model.typelessMicOK ? nil : "打开 Typeless"),
        ]
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
        VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 12) {
                    ProgressView(value: Double(steps.filter { $0.ok }.count), total: Double(steps.count))
                        .tint(steps.allSatisfy { $0.ok } ? .green : .accentColor)
                    Text("\(steps.filter { $0.ok }.count)/\(steps.count) 已完成")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(steps.allSatisfy { $0.ok } ? .green : .primary)
                        .monospacedDigit()
                    Spacer()
                    Button { model.repairSetup() } label: {
                        Label("自动修复", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    Button { model.refreshChecks() } label: {
                        Label("再次检查", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                VStack(spacing: 0) {
                    ForEach(steps) { step in
                        stepRow(step)
                        if step.id != steps.last?.id { Divider().padding(.leading, 42) }
                    }
                }

                if steps.allSatisfy({ $0.ok }) {
                    Label("设置完成，可以直接使用硬件按键。", systemImage: "checkmark.seal.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Label(
                        model.repairNote.isEmpty ? "授权后如果状态没有变化，请等待一秒再点“再次检查”。" : model.repairNote,
                        systemImage: model.repairNote.isEmpty ? "info.circle" : "wrench.and.screwdriver")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        case "audio":
            Permissions.openSound()
        case "typeless", "microphone":
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
