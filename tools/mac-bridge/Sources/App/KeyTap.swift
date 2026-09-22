import ApplicationServices
import Carbon
import AppKit
import CoreGraphics
import FoloVibeCore
import Foundation

/// Sends keystrokes to whatever has focus. Everything the device triggers ends
/// up here, and every shortcut is one the user recorded, so this knows nothing
/// about which application receives it.
enum KeyTap {
    /// Sends a recorded shortcut the way it was configured.
    static func send(_ stroke: KeyStroke) {
        Log.key("发送 \(stroke.display)")
        switch stroke.style {
        case .tap:
            deliver(stroke)
        case .double:
            // A double press has to look like a finger: press, hold, release,
            // pause, again. Two events posted back to back read as a single
            // press to the input methods that listen for this.
            DispatchQueue.global(qos: .userInteractive).async {
                deliver(stroke, holdMs: 45)
                usleep(140_000)
                deliver(stroke, holdMs: 45)
            }
        case .hold:
            // Held long enough to pass for a deliberate press-and-hold, which
            // is what push-to-talk and app switchers wait for.
            DispatchQueue.global(qos: .userInteractive).async {
                deliver(stroke, holdMs: 800)
            }
        }
    }

    static func tapReturn() { tapKey(0x24, flags: []) }

    /// A line break that does not submit. Option+Return is what most chat and
    /// messaging apps take for this.
    static func tapNewline() { tapKey(0x24, flags: .maskAlternate) }

    static func tapSelectAll() { tapKey(0x00, flags: .maskCommand) }

    static func tapClearAll() {
        tapSelectAll()
        usleep(30_000)
        tapKey(0x33, flags: [])  // delete
    }

    static var trusted: Bool { AXIsProcessTrusted() }

    static func promptTrust() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - posting

    private static func deliver(_ stroke: KeyStroke, holdMs: UInt32 = 0) {
        if stroke.isMedia {
            postMedia(stroke.keyCode, down: true)
            if holdMs > 0 { usleep(holdMs * 1000) }
            postMedia(stroke.keyCode, down: false)
            return
        }
        let flags = CGEventFlags(rawValue: stroke.modifiers)
        // A modifier on its own — Right Option, Fn — is not a keystroke. It has
        // to be posted as a change of modifier state, held, and released.
        if stroke.isModifierOnly {
            postModifier(stroke.keyCode, flags: modifierFlag(for: stroke.keyCode), down: true)
            if holdMs > 0 { usleep(holdMs * 1000) }
            postModifier(stroke.keyCode, flags: [], down: false)
            return
        }
        keyDown(stroke.keyCode, flags: flags)
        if holdMs > 0 { usleep(holdMs * 1000) }
        keyUp(stroke.keyCode, flags: flags)
    }

    /// The flag a modifier key raises while it is held.
    private static func modifierFlag(for keyCode: UInt16) -> CGEventFlags {
        switch keyCode {
        case 0x37, 0x36: return .maskCommand
        case 0x38, 0x3C: return .maskShift
        case 0x3A, 0x3D: return .maskAlternate
        case 0x3B, 0x3E: return .maskControl
        case 0x3F: return .maskSecondaryFn
        default: return []
        }
    }

    /// Volume and playback keys are not keyboard events at all: they are
    /// system-defined events carrying the key in their data, and nothing
    /// responds to them posted any other way.
    private static func postMedia(_ key: UInt16, down: Bool) {
        let state = down ? 0xA : 0xB
        let data1 = Int((Int(key) << 16) | (state << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            subtype: 8, data1: data1, data2: -1)
        else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }

    private static func postModifier(_ virtualKey: UInt16, flags: CGEventFlags, down: Bool) {
        let src = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: down)
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
}
