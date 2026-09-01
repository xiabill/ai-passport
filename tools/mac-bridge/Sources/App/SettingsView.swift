import FoloVibeCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: SettingsStore

    init(model: AppModel) {
        self.model = model
        self.store = model.settings
    }

    var body: some View {
        ScrollView {
            Form {
                Section(header: Text("连接")) {
                    TextField("设备名前缀", text: prefixBinding)
                    TextField("音频输出设备", text: outputBinding)
                    Toggle("断开后自动重连", isOn: autoReconnect)
                }
                Section(header: Text("输入法按键")) {
                    Picker("Typeless", selection: talkBinding) {
                        ForEach(Hotkey.talkKeys, id: \.name) { Text($0.name).tag($0.name) }
                    }
                    Picker("豆包", selection: doubaoBinding) {
                        ForEach(Hotkey.doubaoKeys, id: \.name) { Text($0.name).tag($0.name) }
                    }
                    Picker("回车", selection: sendBinding) {
                        ForEach(Hotkey.sendKeys, id: \.name) { Text($0.name).tag($0.name) }
                    }
                    Text("中键：单击听写、双击翻译、长按随便问；上键控制豆包；下键发送回车。Typeless 默认 Fn，翻译为 Fn+Shift，随便问为 Fn+Space。")
                        .foregroundColor(.secondary)
                }
                Section(header: Text("闭环补按")) {
                    Toggle("热键没落到 Typeless 时自动补按", isOn: retapOn)
                    HStack {
                        Text("最早")
                        TextField("秒", value: retapFrom, formatter: number)
                            .frame(width: 60)
                        Text("最晚")
                        TextField("秒", value: retapTo, formatter: number)
                            .frame(width: 60)
                        Text("最多")
                        TextField("次", value: retapMax, formatter: intNumber)
                            .frame(width: 50)
                    }
                }
                Section(header: Text("Typeless")) {
                    HStack {
                        Text("轮询间隔（秒）")
                        TextField("秒", value: poll, formatter: number)
                            .frame(width: 70)
                    }
                    Text("当前麦克风：\(model.typelessMicLabel)")
                        .foregroundColor(model.typelessMicOK ? .secondary : .orange)
                }
                Section(header: Text("启动")) {
                    Toggle("开机启动", isOn: loginBinding)
                    Toggle("启动后只留菜单栏，不弹出窗口", isOn: hidden)
                }
                Section {
                    HStack {
                        Button("恢复默认") { store.reset() }
                        Button("打开辅助功能设置") { Permissions.openAccessibility(); KeyTap.promptTrust() }
                        Button("打开蓝牙设置") { Permissions.openBluetooth() }
                    }
                }
            }
            .padding(16)
        }
    }

    private var number: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }
    private var intNumber: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .none
        return f
    }

    private var prefixBinding: Binding<String> {
        Binding(get: { store.current.devicePrefix }, set: { store.current.devicePrefix = $0 })
    }
    private var outputBinding: Binding<String> {
        Binding(get: { store.current.outputDevice }, set: { store.current.outputDevice = $0 })
    }
    private var autoReconnect: Binding<Bool> {
        Binding(get: { store.current.autoReconnect }, set: { store.current.autoReconnect = $0 })
    }
    private var talkBinding: Binding<String> {
        Binding(get: { store.current.talkKey }, set: { store.current.talkKey = $0 })
    }
    private var sendBinding: Binding<String> {
        Binding(get: { store.current.sendKey }, set: { store.current.sendKey = $0 })
    }
    private var doubaoBinding: Binding<String> {
        Binding(get: { store.current.doubaoKey }, set: { store.current.doubaoKey = $0 })
    }
    private var cancelBinding: Binding<String> {
        Binding(get: { store.current.cancelKey }, set: { store.current.cancelKey = $0 })
    }
    private var retapOn: Binding<Bool> {
        Binding(get: { store.current.retapEnabled }, set: { store.current.retapEnabled = $0 })
    }
    private var retapFrom: Binding<Double> {
        Binding(get: { store.current.retapFromSec }, set: { store.current.retapFromSec = $0 })
    }
    private var retapTo: Binding<Double> {
        Binding(get: { store.current.retapToSec }, set: { store.current.retapToSec = $0 })
    }
    private var retapMax: Binding<Int> {
        Binding(get: { store.current.retapMax }, set: { store.current.retapMax = $0 })
    }
    private var poll: Binding<Double> {
        Binding(get: { store.current.typelessPollSec }, set: { store.current.typelessPollSec = $0 })
    }
    private var hidden: Binding<Bool> {
        Binding(get: { store.current.startHidden }, set: { store.current.startHidden = $0 })
    }
    private var loginBinding: Binding<Bool> {
        Binding(
            get: { model.loginOn },
            set: {
                LoginItem.set($0)
                store.current.launchAtLogin = $0
            })
    }
}
