import AppKit
import Foundation
import Observation

/// Bridge to the private `MediaRemote.framework` that NotchNook / Sleeve / Silicio
/// also rely on. Symbols are looked up lazily via `dlsym`; if any of them are
/// missing (future macOS, sandbox, etc.) the bridge falls back to "no media" so
/// the rest of the app degrades gracefully.
///
/// All work is funneled to `MainActor.run` because SwiftUI views observe `info`
/// directly through `@Observable`.
@Observable
@MainActor
final class MediaRemoteBridge {

    private(set) var info: NowPlayingInfo = .init()
    private(set) var isAvailable: Bool = false

    // MARK: - dlsym handles

    private typealias GetInfoFn      = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias GetPlayingFn   = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias GetClientFn    = @convention(c) (DispatchQueue, @escaping (AnyObject?) -> Void) -> Void
    private typealias RegisterFn     = @convention(c) (DispatchQueue) -> Void
    private typealias SendCommandFn  = @convention(c) (Int, [AnyHashable: Any]?) -> Bool

    private let getNowPlayingInfo:      GetInfoFn?
    private let getIsPlaying:           GetPlayingFn?
    private let getNowPlayingClient:    GetClientFn?
    private let registerForNotifs:      RegisterFn?
    private let sendCommandRaw:         SendCommandFn?

    /// `kMRMediaRemoteCommand` raw values; same numbering used since iOS/macOS 10.
    private enum Command: Int {
        case play             = 0
        case pause            = 1
        case togglePlayPause  = 2
        case stop             = 3
        case nextTrack        = 4
        case previousTrack    = 5
    }

    // MARK: - Init / teardown

    init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        let handle = dlopen(path, RTLD_LAZY)

        func sym<T>(_ name: String, as: T.Type) -> T? {
            guard let handle, let raw = dlsym(handle, name) else { return nil }
            return unsafeBitCast(raw, to: T.self)
        }

        getNowPlayingInfo   = sym("MRMediaRemoteGetNowPlayingInfo",                    as: GetInfoFn.self)
        getIsPlaying        = sym("MRMediaRemoteGetNowPlayingApplicationIsPlaying",    as: GetPlayingFn.self)
        getNowPlayingClient = sym("MRMediaRemoteGetNowPlayingClient",                  as: GetClientFn.self)
        registerForNotifs   = sym("MRMediaRemoteRegisterForNowPlayingNotifications",   as: RegisterFn.self)
        sendCommandRaw      = sym("MRMediaRemoteSendCommand",                          as: SendCommandFn.self)

        isAvailable = (getNowPlayingInfo != nil && registerForNotifs != nil)
    }

    /// Subscribe to MediaRemote notifications and prime `info` with the current
    /// state. Safe to call multiple times.
    func start() {
        guard isAvailable else { return }
        registerForNotifs?(.main)

        let nc = NotificationCenter.default
        nc.addObserver(
            forName: .init("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            object:  nil,
            queue:   .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        nc.addObserver(
            forName: .init("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"),
            object:  nil,
            queue:   .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        nc.addObserver(
            forName: .init("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
            object:  nil,
            queue:   .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        refresh()
    }

    /// Pulls the latest info and playback state from MediaRemote and updates `info`.
    func refresh() {
        guard isAvailable, let getNowPlayingInfo, let getIsPlaying else { return }

        getNowPlayingInfo(.main) { [weak self] dict in
            Task { @MainActor in
                guard let self else { return }
                var next = self.info
                next.title        = dict["kMRMediaRemoteNowPlayingInfoTitle"]              as? String
                next.artist       = dict["kMRMediaRemoteNowPlayingInfoArtist"]             as? String
                next.album        = dict["kMRMediaRemoteNowPlayingInfoAlbum"]              as? String
                next.artworkData  = dict["kMRMediaRemoteNowPlayingInfoArtworkData"]        as? Data
                next.duration     = dict["kMRMediaRemoteNowPlayingInfoDuration"]           as? TimeInterval
                next.elapsedTime  = dict["kMRMediaRemoteNowPlayingInfoElapsedTime"]        as? TimeInterval
                next.playbackRate = dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"]       as? Double
                self.info = next
            }
        }

        getIsPlaying(.main) { [weak self] playing in
            Task { @MainActor in
                guard let self else { return }
                if self.info.isPlaying != playing {
                    self.info.isPlaying = playing
                }
            }
        }
    }

    // MARK: - Commands

    func togglePlayPause() { _ = sendCommandRaw?(Command.togglePlayPause.rawValue, nil) }
    func play()            { _ = sendCommandRaw?(Command.play.rawValue,            nil) }
    func pause()           { _ = sendCommandRaw?(Command.pause.rawValue,           nil) }
    func nextTrack()       { _ = sendCommandRaw?(Command.nextTrack.rawValue,       nil) }
    func previousTrack()   { _ = sendCommandRaw?(Command.previousTrack.rawValue,   nil) }
}
