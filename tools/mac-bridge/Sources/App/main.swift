import AppKit
import FoloVibeCore
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBar?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
        statusBar = StatusBar()
        if AppModel.shared.settings.current.launchAtLogin != LoginItem.enabled {
            LoginItem.set(AppModel.shared.settings.current.launchAtLogin)
        }
        if !AppModel.shared.settings.current.startHidden {
            MainWindow.show()
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindow.show()
        return true
    }
}

if CommandLine.arguments.contains("--self-check") {
    let pcm = IMAADPCM.decode(Data([0x04, 0x0C]), predictor: 0, stepIndex: 0)
    precondition(Array(pcm.prefix(3)) == [7, 8, -1])
    precondition(AudioPacket.parse(Data([9, 0, 0, 0, 0, 1]))?.eos == true)
    precondition(LogLine.parse("01:02:03.456 [蓝牙] ping").category == "蓝牙")
    FileHandle.standardError.write(Data("self-check ok\n".utf8))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
