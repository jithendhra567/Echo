import CryptoKit
import Foundation
import SQLite3

/// Thread-safe SQLite store for clipboard history.
/// All public methods are actor-isolated; callers must `await` them.
actor ClipStore {
    // nonisolated(unsafe): accessed from nonisolated init + actor methods;
    // thread safety is guaranteed because init is synchronous and all subsequent
    // access flows through the actor's serial executor.
    nonisolated(unsafe) private var db: OpaquePointer?

    /// Unpinned clips older than this are removed automatically.
    /// User-configurable via the Dashboard (defaults to 30 days).
    private static var retentionTTL: TimeInterval { AppSettings.storedRetentionTTL }

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

    enum SaveResult: Sendable {
        case inserted
        case duplicate(existingID: UUID)
    }

    @discardableResult
    func save(_ clip: Clip) -> SaveResult {
        guard let db else { return .inserted }
        let hash = contentHash(clip.contentData)

        if let existingID = idForContentHash(hash) {
            return .duplicate(existingID: existingID)
        }

        let sql = """
            INSERT OR IGNORE INTO clips
              (id, content_hash, content_data, content_type, source_app_bundle, source_app_name,
               window_title, created_at, is_pinned)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        prepare(db: db, sql: sql) { stmt in
            bindText(stmt, 1, clip.id.uuidString)
            bindText(stmt, 2, hash)
            bindBlob(stmt, 3, clip.contentData)
            bindText(stmt, 4, clip.contentType.rawValue)
            bindText(stmt, 5, clip.sourceAppBundle)
            bindText(stmt, 6, clip.sourceAppName)
            bindText(stmt, 7, clip.windowTitle)
            sqlite3_bind_double(stmt, 8, clip.createdAt.timeIntervalSince1970)
            sqlite3_bind_int(stmt, 9, clip.isPinned ? 1 : 0)
        }
        prune()
        return .inserted
    }

    func idForContentHash(_ hash: String) -> UUID? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id FROM clips WHERE content_hash = ? LIMIT 1;", -1, &stmt, nil) == SQLITE_OK
        else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, hash)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let idStr = columnText(stmt, 0),
              let id = UUID(uuidString: idStr)
        else { return nil }
        return id
    }

    func fetchRecent(limit: Int? = nil) -> [Clip] {
        if let limit { return fetchPage(offset: 0, limit: limit) }
        prune()
        guard let db else { return [] }
        let cutoff = Date().timeIntervalSince1970 - Self.retentionTTL
        let sql = """
            SELECT id, content_data, content_type, source_app_bundle,
                   source_app_name, window_title, created_at, is_pinned,
                   link_title, link_image, link_favicon
            FROM clips
            WHERE is_pinned = 1 OR created_at >= ?
            ORDER BY is_pinned DESC, created_at DESC;
        """
        var clips: [Clip] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, cutoff)
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let clip = parseRow(stmt) { clips.append(clip) }
        }
        return clips
    }

    func fetchPage(offset: Int, limit: Int) -> [Clip] {
        prune()
        guard let db, limit > 0, offset >= 0 else { return [] }
        let cutoff = Date().timeIntervalSince1970 - Self.retentionTTL
        let sql = """
            SELECT id, content_data, content_type, source_app_bundle,
                   source_app_name, window_title, created_at, is_pinned,
                   link_title, link_image, link_favicon
            FROM clips
            WHERE is_pinned = 1 OR created_at >= ?
            ORDER BY is_pinned DESC, created_at DESC
            LIMIT ? OFFSET ?;
        """
        var clips: [Clip] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, cutoff)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        sqlite3_bind_int(stmt, 3, Int32(offset))
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let clip = parseRow(stmt) { clips.append(clip) }
        }
        return clips
    }

    /// Pinned clips are never pruned. Also drops historically captured mega-blobs
    /// that make launcher search scan multi-megabyte strings on every keystroke.
    private static let maxStoredContentBytes = 256 * 1024
    private static let maxStoredImageBytes = 8 * 1024 * 1024

    func prune() {
        guard let db else { return }
        let cutoff = Date().timeIntervalSince1970 - Self.retentionTTL
        prepare(db: db, sql: "DELETE FROM clips WHERE is_pinned = 0 AND created_at < ?;") { stmt in
            sqlite3_bind_double(stmt, 1, cutoff)
        }
        prepare(
            db: db,
            sql: """
                DELETE FROM clips
                WHERE is_pinned = 0
                  AND (
                    (content_type != 'image' AND length(content_data) > ?)
                    OR (content_type = 'image' AND length(content_data) > ?)
                  );
                """
        ) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(Self.maxStoredContentBytes))
            sqlite3_bind_int(stmt, 2, Int32(Self.maxStoredImageBytes))
        }
    }

    func delete(id: UUID) {
        guard let db else { return }
        prepare(db: db, sql: "DELETE FROM clips WHERE id = ?;") { stmt in
            bindText(stmt, 1, id.uuidString)
        }
    }

    /// Removes history. Pinned clips survive unless `includePinned` is set.
    func deleteAll(includePinned: Bool) {
        guard let db else { return }
        let sql = includePinned
            ? "DELETE FROM clips;"
            : "DELETE FROM clips WHERE is_pinned = 0;"
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    func setPin(id: UUID, pinned: Bool) {
        guard let db else { return }
        prepare(db: db, sql: "UPDATE clips SET is_pinned = ? WHERE id = ?;") { stmt in
            sqlite3_bind_int(stmt, 1, pinned ? 1 : 0)
            bindText(stmt, 2, id.uuidString)
        }
    }

    /// Moves an existing clip to the top of recency-sorted lists.
    func bumpTimestamp(id: UUID, to date: Date = Date()) {
        guard let db else { return }
        prepare(db: db, sql: "UPDATE clips SET created_at = ? WHERE id = ?;") { stmt in
            sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970)
            bindText(stmt, 2, id.uuidString)
        }
    }

    func updateLinkMetadata(
        id: UUID,
        title: String?,
        imageData: Data?,
        faviconData: Data?
    ) {
        guard let db else { return }
        let sql = """
            UPDATE clips
            SET link_title = ?, link_image = ?, link_favicon = ?
            WHERE id = ?;
        """
        prepare(db: db, sql: sql) { stmt in
            bindText(stmt, 1, title)
            bindBlobOrNull(stmt, 2, imageData)
            bindBlobOrNull(stmt, 3, faviconData)
            bindText(stmt, 4, id.uuidString)
        }
    }

    // MARK: - Schema (nonisolated so it can be called from init)

    nonisolated private func createSchema() {
        let sql = """
            CREATE TABLE IF NOT EXISTS clips (
                id                TEXT PRIMARY KEY,
                content_hash      TEXT UNIQUE,
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
        // Migrations — errors ignored when column already exists
        sqlite3_exec(db, "ALTER TABLE clips ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0;", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE clips ADD COLUMN content_hash TEXT;", nil, nil, nil)
        sqlite3_exec(db, "CREATE UNIQUE INDEX IF NOT EXISTS idx_clips_hash ON clips (content_hash);", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE clips ADD COLUMN link_title TEXT;", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE clips ADD COLUMN link_image BLOB;", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE clips ADD COLUMN link_favicon BLOB;", nil, nil, nil)
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
            isPinned: sqlite3_column_int(stmt, 7) != 0,
            linkTitle: columnText(stmt, 8),
            linkImageData: columnBlob(stmt, 9),
            linkFaviconData: columnBlob(stmt, 10)
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

    private func bindBlobOrNull(_ stmt: OpaquePointer?, _ idx: Int32, _ data: Data?) {
        guard let stmt else { return }
        if let data {
            bindBlob(stmt, idx, data)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    private func columnBlob(_ stmt: OpaquePointer?, _ idx: Int32) -> Data? {
        guard let ptr = sqlite3_column_blob(stmt, idx) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, idx))
        guard count > 0 else { return nil }
        return Data(bytes: ptr, count: count)
    }

    private func columnText(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        sqlite3_column_text(stmt, idx).map { String(cString: $0) }
    }

    nonisolated private func contentHash(_ data: Data) -> String {
        CryptoKit.SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
