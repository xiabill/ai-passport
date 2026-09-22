import Foundation

/// Ready-made shortcuts, so the common cases are a pick rather than a
/// recording session. A preset is just a named stroke: choosing one fills in
/// the same field the recorder would, and it can be adjusted afterwards.
public struct KeyPreset: Identifiable, Equatable {
    public let id: String
    /// What the picker calls it.
    public let title: String
    /// What the device screen says, kept short enough for a key cap.
    public let short: String
    public let stroke: KeyStroke

    public enum Group: String, CaseIterable {
        case text = "文本"
        case edit = "编辑"
        case window = "窗口与应用"
        case system = "系统与媒体"
    }

    public let group: Group

    private init(_ id: String, _ title: String, _ short: String, _ group: Group,
                 _ keyCode: UInt16, _ modifiers: UInt64 = 0, label: String? = nil,
                 media: Bool = false) {
        self.id = id
        self.title = title
        self.short = short
        self.group = group
        self.stroke = KeyStroke(
            keyCode: keyCode, modifiers: modifiers,
            label: label ?? title, isMedia: media)
    }

    public static func find(_ id: String) -> KeyPreset? { all.first { $0.id == id } }

    public static func grouped(_ group: Group) -> [KeyPreset] { all.filter { $0.group == group } }

    public static let all: [KeyPreset] = [
        // 文本
        KeyPreset("return", "发送回车", "发送", .text, 0x24, label: "↩"),
        KeyPreset("newline", "换行（不发送）", "换行", .text, 0x24, KeyStroke.option, label: "⌥↩"),
        KeyPreset("escape", "取消 Esc", "取消", .text, 0x35, label: "esc"),
        KeyPreset("tab", "Tab", "Tab", .text, 0x30, label: "⇥"),
        KeyPreset("space", "空格", "空格", .text, 0x31, label: "空格"),
        // 编辑
        KeyPreset("copy", "复制", "复制", .edit, 0x08, KeyStroke.command, label: "⌘C"),
        KeyPreset("paste", "粘贴", "粘贴", .edit, 0x09, KeyStroke.command, label: "⌘V"),
        KeyPreset("cut", "剪切", "剪切", .edit, 0x07, KeyStroke.command, label: "⌘X"),
        KeyPreset("undo", "撤销", "撤销", .edit, 0x06, KeyStroke.command, label: "⌘Z"),
        KeyPreset("redo", "重做", "重做", .edit, 0x06, KeyStroke.command | KeyStroke.shift,
                  label: "⇧⌘Z"),
        KeyPreset("selectAll", "全选", "全选", .edit, 0x00, KeyStroke.command, label: "⌘A"),
        KeyPreset("delete", "删除", "删除", .edit, 0x33, label: "⌫"),
        KeyPreset("save", "保存", "保存", .edit, 0x01, KeyStroke.command, label: "⌘S"),
        KeyPreset("find", "查找", "查找", .edit, 0x03, KeyStroke.command, label: "⌘F"),
        // 窗口与应用
        KeyPreset("switchApp", "切换应用", "切换", .window, 0x30, KeyStroke.command, label: "⌘⇥"),
        KeyPreset("closeWindow", "关闭窗口", "关闭", .window, 0x0D, KeyStroke.command, label: "⌘W"),
        KeyPreset("newTab", "新建标签页", "新标签", .window, 0x11, KeyStroke.command, label: "⌘T"),
        KeyPreset("reload", "刷新", "刷新", .window, 0x0F, KeyStroke.command, label: "⌘R"),
        KeyPreset("spotlight", "聚焦搜索", "搜索", .window, 0x31, KeyStroke.command, label: "⌘空格"),
        // 系统与媒体
        KeyPreset("screenshot", "截图选区", "截图", .system, 0x15,
                  KeyStroke.command | KeyStroke.shift, label: "⇧⌘4"),
        KeyPreset("screenshotClip", "截图到剪贴板", "截剪", .system, 0x15,
                  KeyStroke.command | KeyStroke.shift | KeyStroke.control, label: "⌃⇧⌘4"),
        KeyPreset("playPause", "播放 / 暂停", "播放", .system, MediaKey.playPause, media: true),
        KeyPreset("nextTrack", "下一曲", "下一曲", .system, MediaKey.next, media: true),
        KeyPreset("prevTrack", "上一曲", "上一曲", .system, MediaKey.previous, media: true),
        KeyPreset("volumeUp", "音量 +", "音量+", .system, MediaKey.volumeUp, media: true),
        KeyPreset("volumeDown", "音量 −", "音量−", .system, MediaKey.volumeDown, media: true),
        KeyPreset("mute", "静音", "静音", .system, MediaKey.mute, media: true),
    ]
}

/// System media key codes, as the auxiliary-control event wants them.
public enum MediaKey {
    public static let volumeUp: UInt16 = 0
    public static let volumeDown: UInt16 = 1
    public static let mute: UInt16 = 7
    public static let playPause: UInt16 = 16
    public static let next: UInt16 = 17
    public static let previous: UInt16 = 18
}
