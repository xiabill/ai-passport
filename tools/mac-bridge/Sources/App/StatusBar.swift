import AppKit
import FoloVibeCore

final class StatusBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let phaseItem = NSMenuItem()
    private let lastActionItem = NSMenuItem()
    private let problemItem = NSMenuItem()
    private let handoffItem = NSMenuItem()

    override init() {
        super.init()
        let menu = NSMenu()
        menu.autoenablesItems = false
        phaseItem.isEnabled = false
        lastActionItem.isEnabled = false
        problemItem.isEnabled = false
        menu.addItem(phaseItem)
        menu.addItem(lastActionItem)
        menu.addItem(problemItem)
        menu.addItem(.separator())
        menu.addItem(action("打开主窗口", #selector(open), "1"))
        menu.addItem(action("重连设备", #selector(reconnect), "r"))
        menu.addItem(handoffItem)
        handoffItem.target = self
        handoffItem.action = #selector(handoff)
        menu.addItem(.separator())
        menu.addItem(action("退出", #selector(quit), "q"))
        menu.delegate = self
        item.menu = menu
        item.button?.image = NSImage(systemSymbolName: "waveform.and.mic", accessibilityDescription: "FoloVibe Bridge")
        item.button?.image?.isTemplate = true
        item.button?.title = ""
        item.button?.toolTip = "FoloVibe Bridge"
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func action(_ title: String, _ sel: Selector, _ key: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        it.target = self
        return it
    }

    private func refresh() {
        let m = AppModel.shared
        let snap = m.bleSnap
        item.button?.toolTip = snap.streaming ? "FoloVibe Bridge · 正在输入" : "FoloVibe Bridge · \(snap.phase)"
        phaseItem.title = "设备：\(snap.phase)  \(snap.deviceName)"
        lastActionItem.title = "最近：\(m.lastAction)"
        if !m.axOK { problemItem.title = "辅助功能未开" }
        else if !m.audioOK { problemItem.title = "未找到音频设备" }
        else { problemItem.title = "检查项正常" }
        handoffItem.title = snap.handoffPaused ? "恢复自动连接" : "释放设备给另一台 Mac"
    }

    @objc private func open() { MainWindow.show() }
    @objc private func reconnect() { AppModel.shared.ble.reconnect() }
    @objc private func handoff() {
        guard let ble = AppModel.shared.ble else { return }
        if ble.snapshot.handoffPaused { ble.resumeAfterHandoff() }
        else { ble.releaseForHandoff() }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
