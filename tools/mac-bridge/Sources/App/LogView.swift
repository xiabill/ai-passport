import AppKit
import FoloVibeCore
import SwiftUI

struct LogView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store = LogStore.shared
    @ObservedObject var filter: LogFilter

    init(model: AppModel) {
        self.model = model
        self.filter = model.logFilter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("日志").font(.title2.weight(.semibold))
                Spacer()
                Toggle("自动滚到底", isOn: Binding(get: { filter.autoScroll }, set: { filter.autoScroll = $0 }))
                    .toggleStyle(.checkbox)
                Button("复制可见") { copyVisible() }
                Button("打开文件") { NSWorkspace.shared.open(Log.url) }
                Button("清空") { store.clear() }
            }
            HStack {
                TextField("搜索", text: Binding(get: { filter.search }, set: { filter.search = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                ForEach(LogCategory.all, id: \.self) { cat in
                    Toggle(cat, isOn: Binding(
                        get: { !filter.hidden.contains(cat) },
                        set: { on in
                            if on { filter.hidden.remove(cat) } else { filter.hidden.insert(cat) }
                        }))
                    .toggleStyle(.checkbox)
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(visible) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(line.time).foregroundColor(.secondary).frame(width: 90, alignment: .leading)
                                Text(line.category)
                                    .foregroundColor(color(line.category))
                                    .frame(width: 72, alignment: .leading)
                                Text(line.message)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .id(line.id)
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onReceive(store.$lines) { lines in
                    if filter.autoScroll, let last = visible.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                    _ = lines
                }
            }
        }
        .padding(16)
    }

    private var visible: [LogLine] {
        store.lines.filter { line in
            if !line.category.isEmpty, filter.hidden.contains(line.category) { return false }
            if filter.search.isEmpty { return true }
            return line.message.localizedCaseInsensitiveContains(filter.search)
                || line.category.localizedCaseInsensitiveContains(filter.search)
        }
    }

    private func color(_ cat: String) -> Color {
        switch cat {
        case "蓝牙": return .blue
        case "音频": return .green
        case "按键": return .purple
        case "Typeless": return .orange
        case "调试": return .pink
        default: return .gray
        }
    }

    private func copyVisible() {
        let text = visible.map { "\($0.time) [\($0.category)] \($0.message)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
