import FoloVibeCore
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
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
            if model.activeInputTitle != "—" {
                Text(model.activeInputTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(connectionColor.opacity(0.12), in: Capsule())
        .help(model.bleSnap.deviceName)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.tab {
        case .status: StatusView(model: model)
        case .settings: SettingsView(model: model)
        case .logs: LogView(model: model)
        case .debug: DebugView(model: model)
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
