import AppKit
import FoloVibeCore

final class StatusBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let phaseItem = NSMenuItem()
    private let typelessItem = NSMenuItem()
    private let problemItem = NSMenuItem()

    override init() {
        super.init()
        let menu = NSMenu()
        menu.autoenablesItems = false
        phaseItem.isEnabled = false
        typelessItem.isEnabled = false
        problemItem.isEnabled = false
        menu.addItem(phaseItem)
        menu.addItem(typelessItem)
        menu.addItem(problemItem)
        menu.addItem(.separator())
        menu.addItem(action("打开主窗口", #selector(open), "1"))
        menu.addItem(action("重连设备", #selector(reconnect), "r"))
        menu.addItem(.separator())
        menu.addItem(action("退出", #selector(quit), "q"))
        menu.delegate = self
        item.menu = menu
        item.button?.title = "Vibe"
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
        let title: String
        if snap.streaming { title = "● Vibe" }
        else if snap.subscribed { title = "Vibe" }
        else { title = "○ Vibe" }
        item.button?.title = title
        phaseItem.title = "设备：\(snap.phase)  \(snap.deviceName)"
        typelessItem.title = "输入：\(m.activeInputTitle)  Typeless：\(m.typelessState.title)"
        if !m.axOK { problemItem.title = "辅助功能未开" }
        else if !m.blackholeOK { problemItem.title = "未找到 BlackHole" }
        else if !m.typelessMicOK { problemItem.title = "Typeless 麦克风不匹配" }
        else { problemItem.title = "检查项正常" }
    }

    @objc private func open() { MainWindow.show() }
    @objc private func reconnect() { AppModel.shared.ble.reconnect() }
    @objc private func quit() { NSApp.terminate(nil) }
}
