import Foundation
import ServiceManagement

enum LoginItem {
    private static var cached: (value: Bool, at: Date)?

    static var enabled: Bool {
        if let c = cached, Date().timeIntervalSince(c.at) < 5 { return c.value }
        let value = SMAppService.mainApp.status == .enabled
        cached = (value, Date())
        return value
    }

    static func invalidate() { cached = nil }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            invalidate()
            Log.sys(on ? "已打开开机启动" : "已关闭开机启动")
        } catch {
            Log.sys("开机启动失败：\(error.localizedDescription)")
        }
    }
}
