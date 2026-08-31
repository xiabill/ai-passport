import AppKit
import Foundation
import FoloVibeCore

enum Permissions {
    static func openAccessibility() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for s in urls {
            if let url = URL(string: s) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    static func openBluetooth() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }

    static func typelessMicLabel() -> String? {
        let path = NSHomeDirectory() + "/Library/Application Support/Typeless/app-settings.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let mic = obj["selectedMicrophoneDevice"] as? [String: Any],
            let label = mic["label"] as? String
        else { return nil }
        return label
    }

    static func typelessMicOK(_ outputDevice: String) -> Bool {
        guard let label = typelessMicLabel() else { return false }
        let needle = outputDevice.lowercased()
        return label.lowercased().contains("blackhole") || label.lowercased().contains(needle)
    }
}
