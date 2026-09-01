import AppKit
import Foundation
import FoloVibeCore

enum Permissions {
    @discardableResult
    static func openAccessibility() -> Bool {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        return openSettings(urls)
    }

    @discardableResult
    static func openBluetooth() -> Bool {
        openSettings([
            "x-apple.systempreferences:com.apple.Bluetooth-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.bluetooth",
        ])
    }

    @discardableResult
    static func openSound() -> Bool {
        openSettings([
            "x-apple.systempreferences:com.apple.Sound-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.sound",
        ])
    }

    @discardableResult
    static func openTypeless() -> Bool {
        let candidates = [
            "/Applications/Typeless.app",
            NSHomeDirectory() + "/Applications/Typeless.app",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
        return false
    }

    private static func openSettings(_ strings: [String]) -> Bool {
        for string in strings {
            guard let url = URL(string: string), NSWorkspace.shared.open(url) else { continue }
            return true
        }
        return false
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
