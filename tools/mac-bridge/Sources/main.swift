import AppKit
import ApplicationServices
import Carbon
import Foundation
import SQLite3

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/folovibe-bridge.log")

    static func write(_ msg: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
        FileHandle.standardError.write(Data(line.utf8))
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

enum Keys {
    static func tap(_ keyCode: CGKeyCode) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static func f19() { tap(CGKeyCode(kVK_F19)) }
    static func enter() { tap(CGKeyCode(kVK_Return)) }
    static func escape() { tap(CGKeyCode(kVK_Escape)) }
}

final class TypelessWatch {
    static let dbPath =
        NSHomeDirectory() + "/Library/Application Support/Typeless/typeless.db"
    static let settingsPath =
        NSHomeDirectory() + "/Library/Application Support/Typeless/app-settings.json"
    static let bundleID = "now.typeless.desktop"

    enum State: UInt8 { case idle = 0, recording = 1, processing = 2, down = 3 }
    private var db: OpaquePointer?
    private var stmt: OpaquePointer?
    private(set) var state: State = .idle

    init() {
        _ = sqlite3_open_v2(Self.dbPath, &db, SQLITE_OPEN_READONLY, nil)
        _ = sqlite3_prepare_v2(
            db,
            "select status, duration from history_v2 order by rowid desc limit 1",
            -1, &stmt, nil)
        sqlite3_busy_timeout(db, 50)
    }

    var running: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    func poll() -> State {
        if !running {
            state = .down
            return state
        }
        guard let stmt else { return state }
        sqlite3_reset(stmt)
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            state = .idle
            return state
        }
        let statusNull = sqlite3_column_type(stmt, 0) == SQLITE_NULL
        let durationNull = sqlite3_column_type(stmt, 1) == SQLITE_NULL
        if statusNull && durationNull { state = .recording }
        else if statusNull { state = .processing }
        else { state = .idle }
        return state
    }

    static func warnMic() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let mic = obj["selectedMicrophoneDevice"] as? [String: Any],
            let label = mic["label"] as? String
        else { return }
        if !label.lowercased().contains("blackhole") {
            Log.write("WARN Typeless mic is '\(label)'; set it to BlackHole 2ch")
        }
    }
}

final class App: NSObject, NSApplicationDelegate {
    private var audio: AudioOutput!
    private var ble: BLEClient!
    private var typeless = TypelessWatch()
    private var statusItem: NSStatusItem!
    private var lastHotkey: Date = .distantPast
    private var expect: TypelessWatch.State = .idle
    private var retaps = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        IMAADPCM.selfCheck()
        TypelessWatch.warnMic()
        if !AXIsProcessTrusted() {
            Log.write("WARN Accessibility off: F19/Enter will not reach Typeless")
        }
        audio = AudioOutput()
        do {
            try audio.start(deviceNameContains: "BlackHole 2ch")
            Log.write("BlackHole 2ch output started")
        } catch {
            Log.write("ERROR \(error.localizedDescription)")
        }
        ble = BLEClient(audio: audio)
        ble.onStatus = { Log.write("BLE \($0)") }
        ble.onEvent = { [weak self] ev in self?.handle(ev) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Vibe"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Reconnect", action: #selector(reconnect), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        Log.write("FoloVibe Bridge running")
    }

    @objc private func reconnect() { ble.reconnect() }

    private func handle(_ ev: BLEClient.Event) {
        Log.write("event \(ev)")
        switch ev {
        case .start:
            Keys.f19()
            expect = .recording
            lastHotkey = Date()
            retaps = 0
        case .stop:
            Keys.f19()
            expect = .idle
            lastHotkey = Date()
            retaps = 0
        case .enter:
            Keys.enter()
        case .cancel:
            if ble.streaming { Keys.f19() }
            Keys.escape()
            expect = .idle
            lastHotkey = Date()
        }
    }

    private func tick() {
        let st = typeless.poll()
        ble.writeTypeless(st.rawValue)
        guard typeless.running, retaps < 3 else { return }
        let dt = Date().timeIntervalSince(lastHotkey)
        guard dt >= 2, dt <= 6 else { return }
        if expect == .recording && st != .recording {
            Log.write("retap F19, Typeless still \(st)")
            Keys.f19()
            lastHotkey = Date()
            retaps += 1
        } else if expect == .idle && st == .recording {
            Log.write("retap F19 to stop")
            Keys.f19()
            lastHotkey = Date()
            retaps += 1
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
