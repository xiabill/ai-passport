import AppKit
import FoloVibeCore
import SwiftUI

struct DebugView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: "调试与测试",
                    subtitle: "只在排查问题或验收硬件时使用这些工具")

                SurfaceCard("快捷键测试", subtitle: "焦点要在会接收键盘输入的应用中") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button { KeyTap.tap(model.settings.current.talk) } label: { Label("Typeless", systemImage: "mic") }
                            Button { KeyTap.tap(model.settings.current.doubao) } label: { Label("豆包", systemImage: "mic.fill") }
                            Button { KeyTap.tap(model.settings.current.send) } label: { Label("回车", systemImage: "return") }
                        }
                        Text("如果按键没有反应，请先确认辅助功能权限已开启。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SurfaceCard("模拟硬件事件", subtitle: "不经过 BLE，直接验证 Bridge 的映射和状态闭环") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(VibeEvent.allCases, id: \.self) { ev in
                            Button { model.simulate(ev) } label: {
                                HStack {
                                    Image(systemName: eventSymbol(ev))
                                    Text(ev.title)
                                    Spacer()
                                }
                            }
                        }
                    }
                }

                SurfaceCard("音频工具", subtitle: "确认输出设备和 Passport 麦克风链路") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button { model.audio.playTestTone() } label: { Label("播放测试音", systemImage: "speaker.wave.2") }
                            Button { model.audio.rebuild(reason: "手动") } label: { Label("重建音频引擎", systemImage: "arrow.clockwise") }
                            Button {
                                if model.mic.isArmed { model.mic.cancel() } else { model.mic.arm() }
                            } label: {
                                Label(model.mic.isArmed ? "取消麦测试" : "录一轮设备麦", systemImage: model.mic.isArmed ? "stop.circle" : "record.circle")
                            }
                        }
                        Text(model.mic.result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("先点录音，再在 Passport 上按确定说话，最后按确定停止。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SurfaceCard("连接诊断", subtitle: "用于确认 BLE 服务和音频包是否正常") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button { model.ble.reconnect() } label: { Label("重连 BLE", systemImage: "arrow.triangle.2.circlepath") }
                            Button { copyUUIDs() } label: { Label("复制 UUID", systemImage: "doc.on.doc") }
                        }
                        InfoRow(label: "最近包头", value: model.bleSnap.lastPacketHex.isEmpty ? "—" : model.bleSnap.lastPacketHex)
                            .font(.system(.caption, design: .monospaced))
                        InfoRow(label: "音频包", value: "\(model.bleSnap.packets)")
                        InfoRow(label: "丢包", value: "\(model.bleSnap.lost)", valueColor: model.bleSnap.lost == 0 ? .primary : .orange)
                    }
                }

                SurfaceCard("自检结果") {
                    HStack(spacing: 12) {
                        Button { runSelfCheck() } label: { Label("运行自检", systemImage: "checkmark.seal") }
                        Text(model.debugNote.isEmpty ? "尚未运行" : model.debugNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
    }

    private func eventSymbol(_ event: VibeEvent) -> String {
        switch event {
        case .start, .stop: return "mic"
        case .typelessTranslate: return "character.bubble"
        case .typelessAsk: return "sparkles"
        case .doubaoStart, .doubaoStop, .doubaoStopAndSend: return "mic.fill"
        case .enter: return "return"
        case .cancel: return "xmark.circle"
        }
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
