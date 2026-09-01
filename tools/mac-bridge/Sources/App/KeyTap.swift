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
        if key.name == "Right Option" {
            tapModifier(virtualKey: 0x3D, flags: .maskAlternate)
            return
        }
        if key.name == "Left Option" {
            tapModifier(virtualKey: 0x3A, flags: .maskAlternate)
            return
        }
        tap(key.carbon)
    }

    /// Typeless keeps Dictate, Translation mode, and Ask anything as separate
    /// shortcuts. The latter two use the same base key as Dictate by default:
    /// base+Shift for Translation and base+Space for Ask anything.
    static func tapTypelessTranslate(_ key: Hotkey) {
        tapCombo(key, trigger: nil, modifier: CGEventFlags.maskShift)
    }

    static func tapTypelessAsk(_ key: Hotkey) {
        tapCombo(key, trigger: 0x31, modifier: nil)
    }

    private static func tapCombo(_ key: Hotkey, trigger: UInt16?, modifier: CGEventFlags?) {
        if key.name == "Fn" {
            var flags = CGEventFlags.maskSecondaryFn
            postModifier(virtualKey: functionVirtualKey, flags: flags, down: true)
            if let modifier {
                flags.formUnion(modifier)
                postModifier(virtualKey: 0x38, flags: flags, down: true)
                postModifier(virtualKey: 0x38, flags: .maskSecondaryFn, down: false)
            }
            if let trigger {
                tapKey(trigger, flags: flags)
            }
            postModifier(virtualKey: functionVirtualKey, flags: [], down: false)
            return
        }

        if let modifier {
            postModifier(virtualKey: 0x38, flags: modifier, down: true)
            if let trigger {
                tapKey(trigger, flags: modifier)
            } else {
                tapKey(key.carbon, flags: modifier)
            }
            postModifier(virtualKey: 0x38, flags: [], down: false)
        } else if let trigger {
            keyDown(key.carbon)
            tapKey(trigger, flags: [])
            keyUp(key.carbon)
        }
    }

    private static func tapModifier(virtualKey: UInt16, flags: CGEventFlags) {
        postModifier(virtualKey: virtualKey, flags: flags, down: true)
        postModifier(virtualKey: virtualKey, flags: [], down: false)
    }

    private static func postModifier(virtualKey: UInt16, flags: CGEventFlags, down: Bool) {
        let src = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(
            keyboardEventSource: src,
            virtualKey: virtualKey,
            keyDown: down)
        event?.type = .flagsChanged
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    private static func tapKey(_ virtualKey: UInt16, flags: CGEventFlags) {
        keyDown(virtualKey, flags: flags)
        keyUp(virtualKey, flags: flags)
    }

    private static func keyDown(_ virtualKey: UInt16, flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: true)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    private static func keyUp(_ virtualKey: UInt16, flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: false)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
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
