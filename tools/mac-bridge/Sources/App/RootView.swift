import FoloVibeCore
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            statusStrip
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    /// One compact bar replaces the old sidebar: brand, tabs, and live status
    /// on a single row so the full window width goes to the content.
    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                .help("FoloVibe Bridge")

            tabBar

            Spacer(minLength: 8)
            statusPill
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let active = model.tab == tab
                Button {
                    model.tab = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol).font(.system(size: 12, weight: .medium))
                        Text(tab.title).font(.subheadline.weight(active ? .semibold : .regular))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .foregroundStyle(active ? Color.accentColor : Color.secondary)
                    .background(
                        active ? Color.accentColor.opacity(0.13) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help(tab.subtitle)
            }
        }
    }

    /// The sidebar footer used three stacked lines for this. One pill carries
    /// the same information and survives a narrow window.
    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle().fill(connectionColor).frame(width: 8, height: 8)
            Text(connectionTitle)
                .font(.caption.weight(.semibold))
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(connectionColor.opacity(0.12), in: Capsule())
        .help(model.bleSnap.deviceName)
    }

    /// What used to be a whole status page, as one line that is always in
    /// view: each device with its battery, anything that needs attention, and
    /// the last thing a button did.
    private var statusStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if model.bleSnap.devices.filter(\.ready).isEmpty {
                    Label("没有已连接的设备", systemImage: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.bleSnap.devices.filter(\.ready), id: \.id) { d in
                        deviceChip(d)
                    }
                }
                Spacer(minLength: 8)
                if model.lastAction != "—" {
                    Text("最近：\(model.lastAction)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            if !model.handoffNotice.isEmpty {
                strip(model.handoffNotice, "arrow.left.arrow.right.circle.fill", .blue)
            }
            if !model.listenerWarning.isEmpty {
                strip(model.listenerWarning, "exclamationmark.triangle.fill", .orange)
            } else if !model.audioOK {
                strip("找不到音频设备 \(model.settings.current.outputDevice)，到「设备」页换一个",
                      "exclamationmark.triangle.fill", .orange)
            } else if !model.axOK {
                strip("辅助功能没开，按键发不出去", "exclamationmark.triangle.fill", .orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deviceChip(_ d: BLEClient.Device) -> some View {
        HStack(spacing: 5) {
            Circle().fill(model.bleSnap.streaming ? Color.red : .green).frame(width: 7, height: 7)
            Text(d.name).fontWeight(.medium)
            if let b = d.battery {
                Image(systemName: batterySymbol(b, d.charging))
                    .foregroundStyle(d.charging ? .green : b <= 15 ? .red : .secondary)
                Text("\(b)%").monospacedDigit()
                    .foregroundStyle(b <= 15 && !d.charging ? .red : .secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.05), in: Capsule())
    }

    private func batterySymbol(_ pct: Int, _ charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch pct {
        case 75...: return "battery.100percent"
        case 50..<75: return "battery.75percent"
        case 25..<50: return "battery.50percent"
        case 10..<25: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private func strip(_ text: String, _ symbol: String, _ tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.tab {
        case .keys: SettingsView(model: model, page: .keys)
        case .devices: SettingsView(model: model, page: .devices)
        case .general: SettingsView(model: model, page: .general)
        }
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
}
