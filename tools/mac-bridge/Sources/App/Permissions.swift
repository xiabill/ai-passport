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
    static func openBlackHoleDownload() -> Bool {
        guard let url = URL(string: "https://existential.audio/blackhole/") else { return false }
        return NSWorkspace.shared.open(url)
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

    /// The link only works when Typeless listens to the very device the Bridge
    /// writes into. A hardcoded "blackhole" match used to report success even
    /// when the two sides pointed at different devices.
    static func typelessMicOK(_ outputDevice: String) -> Bool {
        guard let label = typelessMicLabel() else { return false }
        return label.caseInsensitiveCompare(outputDevice) == .orderedSame
            || label.localizedCaseInsensitiveContains(outputDevice)
    }

    static var typelessSettingsPath: String {
        NSHomeDirectory() + "/Library/Application Support/Typeless/app-settings.json"
    }

    static var typelessRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "now.typeless.desktop")
            .isEmpty
    }

    /// Input devices Typeless itself enumerated. Chromium does not always see
    /// every CoreAudio device, so a device missing from this list cannot be
    /// selected inside Typeless no matter what the system reports.
    static func typelessVisibleMics() -> [[String: Any]] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: typelessSettingsPath)),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devices = obj["microphoneDevices"] as? [[String: Any]]
        else { return [] }
        return devices.filter { ($0["kind"] as? String) == "audioinput" }
    }

    static func typelessVisibleMicLabels() -> [String] {
        typelessVisibleMics().compactMap { $0["label"] as? String }
            .filter { !$0.hasPrefix("Auto-detect") }
    }

    /// Points Typeless at `label`, keeping a one-time backup. Typeless caches
    /// settings in memory and rewrites the file on quit, so this is only safe
    /// while it is not running; the caller is responsible for that.
    @discardableResult
    static func setTypelessMic(_ label: String) -> Bool {
        let url = URL(fileURLWithPath: typelessSettingsPath)
        guard let data = try? Data(contentsOf: url),
            var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devices = obj["microphoneDevices"] as? [[String: Any]],
            let match = devices.first(where: { ($0["label"] as? String) == label })
        else { return false }

        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("app-settings.json.folovibe-backup")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try? data.write(to: backup)
        }
        obj["selectedMicrophoneDevice"] = match
        guard let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
        else { return false }
        // Atomic: a half-written settings file would break Typeless on launch.
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent("app-settings.json.folovibe-tmp")
        guard (try? out.write(to: tmp)) != nil else { return false }
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
    }
}
