import AppKit
import FoloVibeCore
import Foundation
import SQLite3

final class TypelessWatch {
    static let dbPath =
        NSHomeDirectory() + "/Library/Application Support/Typeless/typeless.db"
    static let bundleID = "now.typeless.desktop"

    private var db: OpaquePointer?
    private var stmt: OpaquePointer?
    private(set) var state: TypelessState = .idle
    private(set) var dbOK = false

    init() {
        dbOK = sqlite3_open_v2(Self.dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
            && sqlite3_prepare_v2(
                db,
                "select status, duration from history_v2 order by rowid desc limit 1",
                -1, &stmt, nil) == SQLITE_OK
        if dbOK { sqlite3_busy_timeout(db, 50) }
        else { Log.typeless("打不开 \(Self.dbPath)") }
    }

    var running: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    func poll() -> TypelessState {
        if !running {
            state = .down
            return state
        }
        guard dbOK, let stmt else {
            state = .idle
            return state
        }
        sqlite3_reset(stmt)
        let hasRow = sqlite3_step(stmt) == SQLITE_ROW
        let statusNull = hasRow && sqlite3_column_type(stmt, 0) == SQLITE_NULL
        let durationNull = hasRow && sqlite3_column_type(stmt, 1) == SQLITE_NULL
        state = TypelessState.derive(
            running: true, hasRow: hasRow, statusNull: statusNull, durationNull: durationNull)
        return state
    }
}
