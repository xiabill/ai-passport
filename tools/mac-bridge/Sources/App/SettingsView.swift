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
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "设置",
                    subtitle: "把硬件按键和两个输入法配置成你的工作流",
                    trailing: AnyView(Button("恢复默认") { store.reset() }))

                SetupGuideView(model: model)

                SurfaceCard("连接设备", subtitle: "Bridge 会自动寻找名称以此前缀开头的 Passport") {
                    VStack(spacing: 15) {
                        SettingRow("设备名前缀", subtitle: "默认 FoloVibe") {
                            TextField("FoloVibe", text: prefixBinding)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                        }
                        SettingRow("音频输出设备", subtitle: "Typeless 和 Bridge 使用同一个虚拟音频设备") {
                            TextField("BlackHole 2ch", text: outputBinding)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                        }
                        Divider()
                        Toggle(isOn: autoReconnect) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("断开后自动重连").font(.callout.weight(.medium))
                                Text("设备重新出现时自动恢复连接").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                SurfaceCard("硬件按键", subtitle: "每个动作都显示在硬件上，避免记忆复杂快捷键") {
                    VStack(alignment: .leading, spacing: 14) {
                        keyRow("中键 · 单击", "Typeless 语音输入", talkBinding, Hotkey.talkKeys, .blue, "mic.fill")
                        keyRow("中键 · 双击", "Typeless 翻译（自动追加 Shift）", talkBinding, Hotkey.talkKeys, .purple, "character.bubble")
                        keyRow("中键 · 长按", "Typeless 随便问（自动追加 Space）", talkBinding, Hotkey.talkKeys, .orange, "sparkles")
                        Divider()
                        keyRow("上键", "豆包语音输入", doubaoBinding, Hotkey.doubaoKeys, .green, "mic")
                        keyRow("下键", "发送回车", sendBinding, Hotkey.sendKeys, .accentColor, "return")
                        Text("当前约定：Typeless 默认 Fn；翻译为 Fn + Shift；随便问为 Fn + Space。豆包使用免按模式。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SurfaceCard("Typeless 闭环", subtitle: "Bridge 会观察 Typeless 状态，在快捷键没有生效时自动补按") {
                    VStack(alignment: .leading, spacing: 15) {
                        Toggle(isOn: retapOn) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("启用自动补按").font(.callout.weight(.medium))
                                Text("只在检测到状态不一致时补按，不改变正常输入流程").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 12) {
                            valueField("开始等待", value: retapFrom, suffix: "秒")
                            valueField("结束等待", value: retapTo, suffix: "秒")
                            valueField("最多补按", value: retapMax, suffix: "次")
                        }
                        Divider()
                        SettingRow("状态轮询", subtitle: "读取 Typeless 最近状态的间隔") {
                            HStack(spacing: 6) {
                                TextField("2", value: poll, formatter: number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 72)
                                Text("秒").foregroundStyle(.secondary)
                            }
                        }
                        Label(
                            model.typelessMicOK ? "当前麦克风：\(model.typelessMicLabel)" : "当前麦克风不匹配：\(model.typelessMicLabel)",
                            systemImage: model.typelessMicOK ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(model.typelessMicOK ? .green : .orange)
                    }
                }

                SurfaceCard("启动与权限", subtitle: "这些选项只影响 Bridge 自身，不会修改 Typeless 设置") {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: loginBinding) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("开机启动").font(.callout.weight(.medium))
                                Text("登录 macOS 后自动启动 Bridge").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Toggle(isOn: hidden) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("启动后只留菜单栏").font(.callout.weight(.medium))
                                Text("适合日常使用，仍可从菜单栏重新打开窗口").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        HStack(spacing: 10) {
                            Button("打开辅助功能") { Permissions.openAccessibility(); KeyTap.promptTrust() }
                            Button("打开蓝牙设置") { Permissions.openBluetooth() }
                            Button("再次检查") { model.refreshChecks() }
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
    }

    private func keyRow(
        _ title: String,
        _ subtitle: String,
        _ binding: Binding<String>,
        _ keys: [Hotkey],
        _ tint: Color,
        _ symbol: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: binding) {
                ForEach(keys, id: \.name) { Text($0.name).tag($0.name) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 150, alignment: .trailing)
        }
    }

    private func valueField(_ label: String, value: Binding<Double>, suffix: String) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                TextField(label, value: value, formatter: number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 76)
            }
            Text(suffix).font(.caption).foregroundStyle(.secondary).padding(.top, 18)
        }
    }

    private func valueField(_ label: String, value: Binding<Int>, suffix: String) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                TextField(label, value: value, formatter: intNumber)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 76)
            }
            Text(suffix).font(.caption).foregroundStyle(.secondary).padding(.top, 18)
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
