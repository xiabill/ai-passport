import ApplicationServices
import Carbon
import FoloVibeCore
import Foundation

enum KeyTap {
    static func tap(_ carbon: UInt16) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: carbon, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: carbon, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static func tap(_ key: Hotkey) {
        Log.key("发送 \(key.name)")
        tap(key.carbon)
    }

    static var trusted: Bool { AXIsProcessTrusted() }

    static func promptTrust() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}
