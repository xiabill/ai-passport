import FoloVibeCore
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("FoloVibe")
                    .font(.title2.weight(.semibold))
                    .padding(.bottom, 8)
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button(action: { model.tab = tab }) {
                        HStack {
                            Text(tab.rawValue)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(model.tab == tab ? Color.accentColor.opacity(0.18) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                statusFooter
            }
            .padding(14)
            .frame(width: 168)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            Group {
                switch model.tab {
                case .status: StatusView(model: model)
                case .settings: SettingsView(model: model)
                case .logs: LogView(model: model)
                case .debug: DebugView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(model.bleSnap.phase).font(.caption).foregroundColor(.secondary)
            }
            Text(model.typelessState.title).font(.caption).foregroundColor(.secondary)
            Text("输入：\(model.activeInputTitle)").font(.caption).foregroundColor(.secondary)
        }
    }

    private var dot: Color {
        if model.bleSnap.streaming { return .red }
        if model.bleSnap.subscribed { return .green }
        if model.bleSnap.connected { return .yellow }
        return .gray
    }
}
