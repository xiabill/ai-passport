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
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                title: "日志",
                subtitle: "按时间查看蓝牙、音频、按键和 Typeless 事件",
                trailing: AnyView(
                    HStack(spacing: 8) {
                        Button { NSWorkspace.shared.open(Log.url) } label: {
                            Label("打开文件", systemImage: "folder")
                        }
                        Button { copyVisible() } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) { store.clear() } label: {
                            Label("清空", systemImage: "trash")
                        }
                    }))
            HStack(spacing: 10) {
                Label("\(visible.count) 条", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("搜索日志", text: Binding(get: { filter.search }, set: { filter.search = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Spacer()
                Toggle("自动滚动", isOn: Binding(get: { filter.autoScroll }, set: { filter.autoScroll = $0 }))
                    .toggleStyle(.checkbox)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            filterBar
            ScrollViewReader { proxy in
                ScrollView {
                    if visible.isEmpty {
                        EmptyStateView(
                            symbol: "doc.text.magnifyingglass",
                            title: "没有匹配的日志",
                            detail: "尝试清除搜索或打开更多分类")
                    } else {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(visible) { line in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(line.time)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 86, alignment: .leading)
                                    Text(line.category)
                                        .foregroundStyle(color(line.category))
                                        .frame(width: 66, alignment: .leading)
                                    Text(line.message)
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                    Spacer(minLength: 0)
                                }
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                                .id(line.id)
                            }
                        }
                        .padding(12)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)) }
                .onReceive(store.$lines) { lines in
                    if filter.autoScroll, let last = visible.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                    _ = lines
                }
            }
        }
        .frame(maxWidth: 1080, maxHeight: .infinity, alignment: .leading)
        .padding(28)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("分类")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(LogCategory.all, id: \.self) { cat in
                    let enabled = !filter.hidden.contains(cat)
                    Button {
                        if enabled { filter.hidden.insert(cat) } else { filter.hidden.remove(cat) }
                    } label: {
                        Text(cat)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(enabled ? color(cat) : .secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background((enabled ? color(cat) : Color.primary).opacity(0.1), in: Capsule())
                            .overlay { Capsule().strokeBorder((enabled ? color(cat) : Color.primary).opacity(0.12)) }
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
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
