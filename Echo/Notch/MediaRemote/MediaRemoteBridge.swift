import AppKit
import Foundation
import Observation

/// Bridge to the private `MediaRemote.framework` that NotchNook / Sleeve / Silicio
/// also rely on. Symbols are looked up lazily via `dlsym`; if any of them are
/// missing (future macOS, sandbox, etc.) the bridge falls back to "no media" so
/// the rest of the app degrades gracefully.
///
/// **Callback ABI:** `MRMediaRemoteGetNowPlayingInfo` invokes the block with
/// **`[String: Any]?`** (nil when nothing is registered). Typing the parameter as
/// non-optional `[String: Any]` mis-bridges the pointer and yields empty metadata
/// even while Control Center / menu bar still show YouTube or Safari.
///
/// **Queues:** Fetches run on a background queue; MediaRemote can stall if both
/// the registration queue and the completion queue are the same busy main queue.
///
/// **Do not call** `MRMediaRemoteGetNowPlayingClient` from Echo: on recent macOS
/// it can make MediaRemote attribute follow-up work to this process (`playbackQueue<…Echo…>`)
/// and log `kMRMediaRemoteFrameworkErrorDomain` code **35** (“Could not find the
/// specified now playing client”). Bundle id is taken from the now-playing dict instead.
@Observable
@MainActor
final class MediaRemoteBridge {

    private(set) var info: NowPlayingInfo = .init()
    private(set) var isAvailable: Bool = false

    private var didStart = false
    private var notificationTokens: [NSObjectProtocol] = []
    private var pollTimer: Timer?

    /// Reads now playing on a utility queue; `refresh()` merges on the main actor.
    private let mediaRemoteQueue = DispatchQueue(label: "echo.mediaremote", qos: .userInitiated)

    // MARK: - dlsym handles

    /// Second parameter is **`[String: Any]?`** — must match `MRMediaRemoteGetNowPlayingInfo`.
    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
    private typealias GetPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias SendCommandFn = @convention(c) (Int, [AnyHashable: Any]?) -> Bool

    private let getNowPlayingInfo: GetInfoFn?
    private let getIsPlaying: GetPlayingFn?
    private let registerForNotifs: RegisterFn?
    private let sendCommandRaw: SendCommandFn?

    private enum Command: Int {
        case play             = 0
        case pause            = 1
        case togglePlayPause  = 2
        case stop             = 3
        case nextTrack        = 4
        case previousTrack    = 5
    }

    /// Core now-playing notifications only. Queue / content notifications make
    /// MediaRemote resolve per-client playback queues and can spam code 35 when
    /// the resolved path does not match a real player for this process.
    private static let nowPlayingNotificationNames: [String] = [
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification",
    ]

    // MARK: - Init

    init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        let handle = dlopen(path, RTLD_LAZY)

        func sym<T>(_ name: String, as: T.Type) -> T? {
            guard let handle, let raw = dlsym(handle, name) else { return nil }
            return unsafeBitCast(raw, to: T.self)
        }

        getNowPlayingInfo = sym("MRMediaRemoteGetNowPlayingInfo", as: GetInfoFn.self)
        getIsPlaying = sym("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetPlayingFn.self)
        registerForNotifs = sym("MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterFn.self)
        sendCommandRaw = sym("MRMediaRemoteSendCommand", as: SendCommandFn.self)

        isAvailable = (getNowPlayingInfo != nil && registerForNotifs != nil)
    }

    func start() {
        guard isAvailable else { return }
        guard !didStart else {
            refresh()
            return
        }
        didStart = true

        registerForNotifs?(.main)

        let nc = NotificationCenter.default
        for name in Self.nowPlayingNotificationNames {
            let token = nc.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            notificationTokens.append(token)
        }

        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        refresh()
    }

    // MARK: - Refresh

    func refresh() {
        guard isAvailable, let getNowPlayingInfo, let getIsPlaying else { return }

        let bg = mediaRemoteQueue

        getNowPlayingInfo(bg) { [weak self] rawDict in
            guard let self else { return }
            let normalized = Self.normalizeStringKeyedDictionary(rawDict)

            getIsPlaying(bg) { playing in
                Task { @MainActor in
                    self.applyNowPlaying(normalized, isPlaying: playing)
                }
            }
        }
    }

    private func applyNowPlaying(_ dict: [String: Any], isPlaying: Bool) {
        var next = info
        next.isPlaying = isPlaying

        guard !dict.isEmpty else {
            next.title = nil
            next.artist = nil
            next.album = nil
            next.artworkData = nil
            next.duration = nil
            next.elapsedTime = nil
            next.playbackRate = nil
            next.clientBundleID = nil
            info = next
            return
        }

        next.clientBundleID = Self.firstString(
            dict,
            keys: [
                "kMRMediaRemoteNowPlayingApplicationBundleIdentifier",
                "MRMediaRemoteNowPlayingApplicationBundleIdentifier",
            ]
        )
        next.title = Self.firstString(
            dict,
            keys: [
                "kMRMediaRemoteNowPlayingInfoTitle",
                "title",
            ]
        )
        next.artist = Self.firstString(
            dict,
            keys: [
                "kMRMediaRemoteNowPlayingInfoArtist",
                "kMRMediaRemoteNowPlayingInfoAlbumArtist",
                "artist",
            ]
        )
        next.album = Self.firstString(
            dict,
            keys: [
                "kMRMediaRemoteNowPlayingInfoAlbum",
                "album",
            ]
        )
        next.artworkData = Self.firstData(
            dict,
            keys: [
                "kMRMediaRemoteNowPlayingInfoArtworkData",
            ]
        )
        next.duration = Self.firstDouble(
            dict,
            keys: ["kMRMediaRemoteNowPlayingInfoDuration"]
        )
        next.elapsedTime = Self.firstDouble(
            dict,
            keys: [
                "kMRMediaRemoteNowPlayingInfoElapsedTime",
                "kMRMediaRemoteNowPlayingInfoTimestamp",
            ]
        )
        next.playbackRate = Self.firstDouble(
            dict,
            keys: ["kMRMediaRemoteNowPlayingInfoPlaybackRate"]
        )
        info = next
    }

    /// Bridges `NSDictionary` / mixed keys to `[String: Any]` with `String` keys.
    private static func normalizeStringKeyedDictionary(_ raw: [String: Any]?) -> [String: Any] {
        guard let raw else { return [:] }
        var out: [String: Any] = [:]
        for (k, v) in raw {
            if let s = k as? String {
                out[s] = v
            } else if let s = k as? NSString {
                out[s as String] = v
            }
        }
        return out
    }

    private static func firstString(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let s = coercedString(dict[key]) { return s }
        }
        return nil
    }

    private static func firstDouble(_ dict: [String: Any], keys: [String]) -> TimeInterval? {
        for key in keys {
            if let d = coercedDouble(dict[key]) { return d }
        }
        return nil
    }

    private static func firstData(_ dict: [String: Any], keys: [String]) -> Data? {
        for key in keys {
            if let d = coercedData(dict[key]) { return d }
        }
        return nil
    }

    private static func coercedString(_ any: Any?) -> String? {
        switch any {
        case let s as String:
            return s.isEmpty ? nil : s
        case let s as NSString:
            let t = s as String
            return t.isEmpty ? nil : t
        case let n as NSNumber:
            return n.stringValue
        default:
            return nil
        }
    }

    private static func coercedDouble(_ any: Any?) -> TimeInterval? {
        switch any {
        case let d as Double: return d
        case let d as TimeInterval: return d
        case let n as NSNumber: return n.doubleValue
        case let d as CGFloat: return Double(d)
        default: return nil
        }
    }

    private static func coercedData(_ any: Any?) -> Data? {
        switch any {
        case let d as Data: return d.isEmpty ? nil : d
        case let d as NSData:
            let b = d as Data
            return b.isEmpty ? nil : b
        default: return nil
        }
    }

    // MARK: - Commands

    func togglePlayPause() { _ = sendCommandRaw?(Command.togglePlayPause.rawValue, nil) }
    func play() { _ = sendCommandRaw?(Command.play.rawValue, nil) }
    func pause() { _ = sendCommandRaw?(Command.pause.rawValue, nil) }
    func nextTrack() { _ = sendCommandRaw?(Command.nextTrack.rawValue, nil) }
    func previousTrack() { _ = sendCommandRaw?(Command.previousTrack.rawValue, nil) }
}
