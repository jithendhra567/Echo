import Foundation
import SQLite3

actor BrowserTabStore {
    nonisolated(unsafe) private var db: OpaquePointer?

    private static let ttl: TimeInterval = 30 * 24 * 3600

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Echo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("browser_tabs.db").path
        guard sqlite3_open(path, &db) == SQLITE_OK else { db = nil; return }
        createSchema()
    }

    deinit { sqlite3_close(db) }

    // MARK: - Public API

    func save(_ tab: BrowserTab) {
        guard let db else { return }
        let now     = Date().timeIntervalSince1970
        let expires = now + Self.ttl
        let sql = """
            INSERT INTO browser_tabs (url, title, browser, last_seen, expires_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(url) DO UPDATE SET
                title     = excluded.title,
                browser   = excluded.browser,
                last_seen = excluded.last_seen;
        """
        prepare(db: db, sql: sql) { stmt in
            bindText(stmt, 1, tab.url)
            bindText(stmt, 2, tab.title)
            bindText(stmt, 3, tab.browser.rawValue)
            sqlite3_bind_double(stmt, 4, now)
            sqlite3_bind_double(stmt, 5, expires)
        }
    }

    /// Extend expiry 30 days from now (called when a saved tab is opened from search).
    func touch(url: String) {
        guard let db else { return }
        let now     = Date().timeIntervalSince1970
        let expires = now + Self.ttl
        prepare(db: db, sql: "UPDATE browser_tabs SET last_seen = ?, expires_at = ? WHERE url = ?;") { stmt in
            sqlite3_bind_double(stmt, 1, now)
            sqlite3_bind_double(stmt, 2, expires)
            bindText(stmt, 3, url)
        }
    }

    func fetchAll() -> [BrowserTab] {
        guard let db else { return [] }
        let sql = """
            SELECT url, title, browser FROM browser_tabs
            WHERE expires_at > ?
            ORDER BY last_seen DESC;
        """
        var tabs: [BrowserTab] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let url       = columnText(stmt, 0),
                  let title     = columnText(stmt, 1),
                  let rawBsr    = columnText(stmt, 2),
                  let browser   = BrowserTab.Browser(rawValue: rawBsr)
            else { continue }
            tabs.append(BrowserTab(id: UUID(), title: title, url: url, browser: browser, isSaved: true))
        }
        return tabs
    }

    func prune() {
        guard let db else { return }
        prepare(db: db, sql: "DELETE FROM browser_tabs WHERE expires_at <= ?;") { stmt in
            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
        }
    }

    // MARK: - Schema

    nonisolated private func createSchema() {
        let sql = """
            CREATE TABLE IF NOT EXISTS browser_tabs (
                url        TEXT PRIMARY KEY,
                title      TEXT NOT NULL,
                browser    TEXT NOT NULL,
                last_seen  REAL NOT NULL,
                expires_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_tabs_expires  ON browser_tabs (expires_at);
            CREATE INDEX IF NOT EXISTS idx_tabs_seen     ON browser_tabs (last_seen DESC);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - SQLite helpers

    private func prepare(db: OpaquePointer, sql: String, bind: (OpaquePointer?) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        sqlite3_step(stmt)
    }

    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String) {
        guard let stmt else { return }
        sqlite3_bind_text(stmt, idx, value, -1,
                          unsafeBitCast(-1 as Int, to: sqlite3_destructor_type.self))
    }

    private func columnText(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        sqlite3_column_text(stmt, idx).map { String(cString: $0) }
    }
}
