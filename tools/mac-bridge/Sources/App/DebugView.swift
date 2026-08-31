import AppKit
import FoloVibeCore
import SwiftUI

struct DebugView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("调试与测试").font(.title2.weight(.semibold))

                group("按键") {
                    HStack {
                        Button("点说话键") { KeyTap.tap(model.settings.current.talk) }
                        Button("点发送键") { KeyTap.tap(model.settings.current.send) }
                        Button("点取消键") { KeyTap.tap(model.settings.current.cancel) }
                    }
                    Text("焦点要在会吃键盘的地方。没开辅助功能时什么都不会发生。")
                        .foregroundColor(.secondary)
                }

                group("模拟设备事件") {
                    HStack {
                        ForEach(VibeEvent.allCases, id: \.self) { ev in
                            Button(ev.title) { model.simulate(ev) }
                        }
                    }
                    Text("不经过 BLE，直接走热键和闭环逻辑。")
                        .foregroundColor(.secondary)
                }

                group("音频") {
                    HStack {
                        Button("440Hz 测试音") { model.audio.playTestTone() }
                        Button("重建音频引擎") { model.audio.rebuild(reason: "手动") }
                        Button(model.mic.isArmed ? "取消麦测试" : "录下一轮设备麦") {
                            if model.mic.isArmed { model.mic.cancel() } else { model.mic.arm() }
                        }
                    }
                    Text(model.mic.result).foregroundColor(.secondary)
                    Text("麦测试：先点按钮，再在 Passport 上按确定说话、再按确定停止，会存 WAV 并用扬声器回放。")
                        .foregroundColor(.secondary)
                }

                group("连接") {
                    HStack {
                        Button("重连 BLE") { model.ble.reconnect() }
                        Button("复制 UUID") { copyUUIDs() }
                    }
                    Text("最近包头：\(model.bleSnap.lastPacketHex.isEmpty ? "—" : model.bleSnap.lastPacketHex)")
                        .font(.system(.body, design: .monospaced))
                    Text("包 \(model.bleSnap.packets) · 丢 \(model.bleSnap.lost) · 推流 \(model.bleSnap.streaming ? "是" : "否")")
                }

                group("自检") {
                    Button("跑内置自检") { runSelfCheck() }
                    Text(model.debugNote).foregroundColor(.secondary)
                }
            }
            .padding(20)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }

    private func copyUUIDs() {
        let text = [
            VibeProtocol.serviceUUID,
            VibeProtocol.audioUUID,
            VibeProtocol.eventUUID,
            VibeProtocol.controlUUID,
        ].joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Log.debug("已复制 UUID")
    }

    private func runSelfCheck() {
        let pcm = IMAADPCM.decode(Data([0x04, 0x0C]), predictor: 0, stepIndex: 0)
        let pkt = AudioPacket.parse(Data([9, 0, 0, 0, 0, 1]))
        let line = LogLine.parse("01:02:03.456 [蓝牙] ping")
        var ok = Array(pcm.prefix(3)) == [7, 8, -1]
        ok = ok && pkt?.eos == true
        ok = ok && line.category == "蓝牙"
        model.debugNote = ok ? "自检通过：ADPCM / 协议 / 日志解析" : "自检失败"
        Log.debug(model.debugNote)
    }
}
