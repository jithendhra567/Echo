import Foundation
import os

enum CurrencyCacheStore: Sendable {

    private nonisolated(unsafe) static let log = Logger(subsystem: "com.echo", category: "CurrencyCache")
    private nonisolated(unsafe) static let lock = NSLock()
    private nonisolated(unsafe) static var memory: CurrencyCacheSnapshot?

    private nonisolated static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Echo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("currency_rates.json")
    }

    nonisolated static func snapshot() -> CurrencyCacheSnapshot {
        lock.lock()
        defer { lock.unlock() }
        if memory == nil {
            memory = loadFromDisk() ?? CurrencyCacheSnapshot(entries: [:], lastCurrencyActivityAt: nil)
        }
        return memory!
    }

    nonisolated static func save(_ snapshot: CurrencyCacheSnapshot) {
        lock.lock()
        memory = snapshot
        lock.unlock()

        do {
            let data = try encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            log.debug("Saved currency cache (\(snapshot.entries.count) pairs)")
        } catch {
            log.error("Failed to save currency cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated static func clear() {
        log.info("Clearing currency cache (inactivity policy)")
        save(CurrencyCacheSnapshot(entries: [:], lastCurrencyActivityAt: nil))
    }

    // MARK: - JSON (nonisolated, no synthesized Codable)

    private nonisolated static func encode(_ snapshot: CurrencyCacheSnapshot) throws -> Data {
        var entriesArray: [[String: Any]] = []
        for entry in snapshot.entries.values {
            entriesArray.append([
                "base": entry.base,
                "target": entry.target,
                "rate": entry.rate,
                "fetchedAt": entry.fetchedAt.timeIntervalSince1970,
                "lastUsed": entry.lastUsed.timeIntervalSince1970,
            ])
        }
        var root: [String: Any] = ["entries": entriesArray]
        if let activity = snapshot.lastCurrencyActivityAt {
            root["lastCurrencyActivityAt"] = activity.timeIntervalSince1970
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private nonisolated static func loadFromDisk() -> CurrencyCacheSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            var entries: [String: CurrencyCacheEntry] = [:]
            if let arr = root["entries"] as? [[String: Any]] {
                for dict in arr {
                    guard let base = dict["base"] as? String,
                          let target = dict["target"] as? String,
                          let rate = dict["rate"] as? Double,
                          let fetched = dict["fetchedAt"] as? TimeInterval,
                          let used = dict["lastUsed"] as? TimeInterval else { continue }
                    let entry = CurrencyCacheEntry(
                        base: base,
                        target: target,
                        rate: rate,
                        fetchedAt: Date(timeIntervalSince1970: fetched),
                        lastUsed: Date(timeIntervalSince1970: used)
                    )
                    entries[CurrencyCacheEntry.key(base: base, target: target)] = entry
                }
            }

            let activity = (root["lastCurrencyActivityAt"] as? TimeInterval).map {
                Date(timeIntervalSince1970: $0)
            }
            let snap = CurrencyCacheSnapshot(entries: entries, lastCurrencyActivityAt: activity)
            log.debug("Loaded currency cache (\(snap.entries.count) pairs)")
            return snap
        } catch {
            log.error("Failed to load currency cache: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
