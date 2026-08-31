import FoloVibeCore
import SwiftUI

struct StatusView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("总览").font(.title2.weight(.semibold))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    card("设备", [
                        ("状态", model.bleSnap.phase),
                        ("名称", model.bleSnap.deviceName),
                        ("RSSI", model.bleSnap.rssi.map { "\($0) dBm" } ?? "—"),
                        ("MTU", "\(model.bleSnap.mtu)"),
                    ])
                    card("音频", [
                        ("推流", model.bleSnap.streaming ? "进行中" : "未推流"),
                        ("包", "\(model.bleSnap.packets)"),
                        ("丢包", "\(model.bleSnap.lost)"),
                        ("峰值", "\(model.audioPeak)"),
                    ])
                    card("Typeless", [
                        ("状态", model.typelessState.title),
                        ("进程", model.typeless.running ? "运行中" : "未打开"),
                        ("麦克风", model.typelessMicLabel),
                        ("快捷键", model.settings.current.talkKey),
                    ])
                    card("输入法", [
                        ("当前", model.activeInputTitle),
                        ("Typeless", model.settings.current.talkKey),
                        ("豆包", model.settings.current.doubaoKey),
                        ("回车", model.settings.current.sendKey),
                    ])
                    card("权限", [
                        ("辅助功能", model.axOK ? "已开" : "未开"),
                        ("系统蓝牙", model.bleSnap.bluetoothOn ? "已开" : "未开"),
                        ("BlackHole", model.blackholeOK ? "已找到" : "未找到"),
                        ("Typeless 麦", model.typelessMicOK ? "匹配" : "不匹配"),
                    ])
                }
                levelBar
                problems
                HStack {
                    Button("重连设备") { model.ble.reconnect() }
                    Button("打开主窗口设置") { model.tab = .settings }
                    Spacer()
                    Text("最近操作：\(model.lastAction)").foregroundColor(.secondary)
                }
            }
            .padding(20)
        }
    }

    private func card(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0).foregroundColor(.secondary)
                    Spacer()
                    Text(row.1)
                }
                .font(.callout)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }

    private var levelBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("输入电平").font(.headline)
            GeometryReader { geo in
                let w = max(4, geo.size.width * CGFloat(min(model.audioPeak, 8000)) / 8000)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.2))
                    Capsule().fill(model.bleSnap.streaming ? Color.red : Color.accentColor)
                        .frame(width: w)
                }
            }
            .frame(height: 10)
        }
    }

    private var problems: some View {
        let items = issueList
        return VStack(alignment: .leading, spacing: 6) {
            Text("检查项").font(.headline)
            if items.isEmpty {
                Text("没有明显问题。").foregroundColor(.secondary)
            } else {
                ForEach(items, id: \.self) { Text("• " + $0) }
            }
        }
    }

    private var issueList: [String] {
        var out = [String]()
        if !model.bleSnap.bluetoothOn { out.append("打开系统蓝牙") }
        if !model.bleSnap.subscribed { out.append("等待 Passport 广播 FoloVibe-* 并靠近 Mac") }
        if !model.axOK { out.append("在系统设置里给 FoloVibe Bridge 打开辅助功能") }
        if !model.blackholeOK {
            out.append("未找到 \(model.settings.current.outputDevice)，请安装 BlackHole 2ch")
        }
        if !model.typeless.running { out.append("打开 Typeless") }
        if model.typeless.running && !model.typelessMicOK {
            out.append("把 Typeless 麦克风改成 \(model.settings.current.outputDevice)")
        }
        return out
    }
}
