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
    /// Doubao's hands-free mode is documented as "double click to start
    /// talking, double click again or press any key to end". It accepts a
    /// physical double click but ignored ours when both presses were posted
    /// back to back with no hold, so this reproduces the timing of a real one:
    /// press, hold briefly, release, pause, repeat. Runs off the main thread
    /// because it sleeps between events.
    static func tapDouble(_ key: Hotkey) {
        Log.key("双击 \(key.name)（豆包免按模式）")
        DispatchQueue.global(qos: .userInteractive).async {
            holdTap(key, holdMs: 45)
            usleep(140_000)
            holdTap(key, holdMs: 45)
        }
    }

    /// A single press that stays down for `holdMs`, like a finger would.
    private static func holdTap(_ key: Hotkey, holdMs: UInt32) {
        let hold = { usleep(holdMs * 1000) }
        switch key.name {
        case "Fn":
            postModifier(virtualKey: functionVirtualKey, flags: .maskSecondaryFn, down: true)
            hold()
            postModifier(virtualKey: functionVirtualKey, flags: [], down: false)
        case "Right Option":
            postModifier(virtualKey: 0x3D, flags: .maskAlternate, down: true)
            hold()
            postModifier(virtualKey: 0x3D, flags: [], down: false)
        case "Left Option":
            postModifier(virtualKey: 0x3A, flags: .maskAlternate, down: true)
            hold()
            postModifier(virtualKey: 0x3A, flags: [], down: false)
        default:
            keyDown(key.carbon)
            hold()
            keyUp(key.carbon)
        }
    }

    static func tapTypelessTranslate(_ key: Hotkey) {
        tapCombo(key, trigger: nil, modifier: CGEventFlags.maskShift)
    }

    static func tapTypelessAsk(_ key: Hotkey) {
        tapCombo(key, trigger: 0x31, modifier: nil)
    }

    /// On macOS, Command+A is the native Select All command (the literal
    /// Control+A binding moves to the beginning of a text field).
    /// Option+Return inserts a line break without submitting, which most chat
    /// and editor fields treat as "new line" rather than "send".
    static func tapNewline() {
        Log.key("发送 Option+Return（换行）")
        postModifier(virtualKey: 0x3A, flags: .maskAlternate, down: true)
        tapKey(0x24, flags: .maskAlternate)
        postModifier(virtualKey: 0x3A, flags: [], down: false)
    }

    static func tapSelectAll() {
        Log.key("发送 Cmd+A（全选）")
        tapCommandKey(0x00) // A
    }

    static func tapClearAll() {
        Log.key("发送全选并删除")
        tapSelectAll()
        tapKey(0x33, flags: []) // Delete / Backspace
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

    private static func tapCommandKey(_ virtualKey: UInt16) {
        postModifier(virtualKey: 0x37, flags: .maskCommand, down: true)
        tapKey(virtualKey, flags: .maskCommand)
        postModifier(virtualKey: 0x37, flags: [], down: false)
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
