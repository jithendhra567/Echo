import Foundation
import SQLite3

/// Thread-safe SQLite store for clipboard history.
/// All public methods are actor-isolated; callers must `await` them.
actor ClipStore {
    // nonisolated(unsafe): accessed from nonisolated init + actor methods;
    // thread safety is guaranteed because init is synchronous and all subsequent
    // access flows through the actor's serial executor.
    nonisolated(unsafe) private var db: OpaquePointer?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Echo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("clips.db").path

        guard sqlite3_open(path, &db) == SQLITE_OK else {
            db = nil
            return
        }
        createSchema()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Public API

    func save(_ clip: Clip) {
        guard let db else { return }
        let sql = """
            INSERT OR REPLACE INTO clips
              (id, content_data, content_type, source_app_bundle, source_app_name,
               window_title, created_at, is_pinned)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        prepare(db: db, sql: sql) { stmt in
            bindText(stmt, 1, clip.id.uuidString)
            bindBlob(stmt, 2, clip.contentData)
            bindText(stmt, 3, clip.contentType.rawValue)
            bindText(stmt, 4, clip.sourceAppBundle)
            bindText(stmt, 5, clip.sourceAppName)
            bindText(stmt, 6, clip.windowTitle)
            sqlite3_bind_double(stmt, 7, clip.createdAt.timeIntervalSince1970)
            sqlite3_bind_int(stmt, 8, clip.isPinned ? 1 : 0)
        }
    }

    func fetchRecent(limit: Int = 50) -> [Clip] {
        guard let db else { return [] }
        let sql = """
            SELECT id, content_data, content_type, source_app_bundle,
                   source_app_name, window_title, created_at, is_pinned
            FROM clips ORDER BY is_pinned DESC, created_at DESC LIMIT ?;
        """
        var clips: [Clip] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let clip = parseRow(stmt) { clips.append(clip) }
        }
        return clips
    }

    func delete(id: UUID) {
        guard let db else { return }
        prepare(db: db, sql: "DELETE FROM clips WHERE id = ?;") { stmt in
            bindText(stmt, 1, id.uuidString)
        }
    }

    func setPin(id: UUID, pinned: Bool) {
        guard let db else { return }
        prepare(db: db, sql: "UPDATE clips SET is_pinned = ? WHERE id = ?;") { stmt in
            sqlite3_bind_int(stmt, 1, pinned ? 1 : 0)
            bindText(stmt, 2, id.uuidString)
        }
    }

    // MARK: - Schema (nonisolated so it can be called from init)

    nonisolated private func createSchema() {
        let sql = """
            CREATE TABLE IF NOT EXISTS clips (
                id                TEXT PRIMARY KEY,
                content_data      BLOB NOT NULL,
                content_type      TEXT NOT NULL,
                source_app_bundle TEXT,
                source_app_name   TEXT,
                window_title      TEXT,
                created_at        REAL NOT NULL,
                is_pinned         INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_clips_time ON clips (is_pinned DESC, created_at DESC);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
        // Migration: add is_pinned to existing databases (error ignored if column exists)
        sqlite3_exec(db, "ALTER TABLE clips ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0;", nil, nil, nil)
    }

    // MARK: - Row parsing

    private func parseRow(_ stmt: OpaquePointer?) -> Clip? {
        guard let idStr   = columnText(stmt, 0),
              let id      = UUID(uuidString: idStr),
              let typeStr = columnText(stmt, 2),
              let type    = ClipContentType(rawValue: typeStr),
              let rawPtr  = sqlite3_column_blob(stmt, 1)
        else { return nil }

        let data = Data(bytes: rawPtr, count: Int(sqlite3_column_bytes(stmt, 1)))
        return Clip(
            id: id,
            contentData: data,
            contentType: type,
            sourceAppBundle: columnText(stmt, 3),
            sourceAppName:   columnText(stmt, 4),
            windowTitle:     columnText(stmt, 5),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6)),
            isPinned: sqlite3_column_int(stmt, 7) != 0
        )
    }

    // MARK: - Binding helpers

    private func prepare(db: OpaquePointer, sql: String, bind: (OpaquePointer?) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        sqlite3_step(stmt)
    }

    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String?) {
        guard let stmt else { return }
        if let value {
            // SQLITE_TRANSIENT (−1 cast): SQLite copies the string before returning
            sqlite3_bind_text(stmt, idx, value, -1,
                              unsafeBitCast(-1 as Int, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    private func bindBlob(_ stmt: OpaquePointer?, _ idx: Int32, _ data: Data) {
        guard let stmt else { return }
        _ = data.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, idx, ptr.baseAddress, Int32(data.count),
                              unsafeBitCast(-1 as Int, to: sqlite3_destructor_type.self))
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        sqlite3_column_text(stmt, idx).map { String(cString: $0) }
    }
}
