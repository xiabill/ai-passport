import FoloVibeCore
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar(removing: .sidebarToggle)
        .toolbar(.hidden, for: .windowToolbar)
        .navigationSplitViewColumnWidth(min: 216, ideal: 242, max: 286)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.and.mic")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.tint)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("FoloVibe").font(.headline.weight(.semibold))
                    Text("Bridge 控制台").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 18)

            List(selection: Binding<AppTab?>(
                get: { model.tab },
                set: { if let tab = $0 { model.tab = tab } })) {
                Section("工作区") {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        Label(tab.title, systemImage: tab.symbol)
                            .font(.subheadline.weight(.medium))
                            .tag(tab)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            sidebarFooter
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 9, height: 9)
                Text(connectionTitle).font(.caption.weight(.semibold))
                Spacer()
            }
            Text(model.bleSnap.deviceName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 5) {
                Image(systemName: "waveform")
                Text(model.activeInputTitle == "—" ? "等待硬件操作" : model.activeInputTitle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 17)
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
