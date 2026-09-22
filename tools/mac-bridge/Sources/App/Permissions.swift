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
    private static func openSettings(_ strings: [String]) -> Bool {
        for string in strings {
            guard let url = URL(string: string), NSWorkspace.shared.open(url) else { continue }
            return true
        }
        return false
    }
}
