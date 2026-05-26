import CoreServices
import Foundation

/// Watches application install folders and notifies when the app index should refresh.
nonisolated final class AppIndexWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private var debounceTask: Task<Void, Never>?
    private let paths: [String]
    private let onChange: @Sendable () -> Void

    init(paths: [String], onChange: @escaping @Sendable () -> Void) {
        self.paths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        self.onChange = onChange
        start()
    }

    deinit { stop() }

    private func start() {
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            UInt32(kFSEventStreamCreateFlagUseCFTypes) |
            UInt32(kFSEventStreamCreateFlagFileEvents)
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<AppIndexWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.scheduleReindex()
        }

        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            flags
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    private func scheduleReindex() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                onChange()
            }
        }
    }

    private func stop() {
        debounceTask?.cancel()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
