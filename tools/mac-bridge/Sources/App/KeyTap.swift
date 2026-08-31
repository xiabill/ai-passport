import ApplicationServices
import Carbon
import CoreGraphics
import FoloVibeCore
import Foundation

enum KeyTap {
    private static let functionVirtualKey: UInt16 = 0x3F

    static func tap(_ carbon: UInt16) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: carbon, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: carbon, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static func tap(_ key: Hotkey) {
        Log.key("发送 \(key.name)")
        if key.name == "Fn" {
            tapFunction()
            return
        }
        tap(key.carbon)
    }

    /// Fn/Globe is a modifier-only key on macOS, so it must be posted as a
    /// flags-changed event with the SecondaryFn flag rather than as F19.
    private static func tapFunction() {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(
            keyboardEventSource: src,
            virtualKey: functionVirtualKey,
            keyDown: true)
        down?.type = .flagsChanged
        down?.flags = .maskSecondaryFn
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(
            keyboardEventSource: src,
            virtualKey: functionVirtualKey,
            keyDown: false)
        up?.type = .flagsChanged
        up?.flags = []
        up?.post(tap: .cghidEventTap)
    }

    static var trusted: Bool { AXIsProcessTrusted() }

    static func promptTrust() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}
