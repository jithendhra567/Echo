import AppKit
import Foundation

/// Snapshot of the currently active media app, as exposed by the system-wide
/// MediaRemote framework. Pure value type so it composes nicely with `@Observable`
/// and SwiftUI diffing.
struct NowPlayingInfo: Equatable, Sendable {
    var title:        String?
    var artist:       String?
    var album:        String?
    var artworkData:  Data?
    var duration:     TimeInterval?
    var elapsedTime:  TimeInterval?
    var playbackRate: Double?
    /// Bundle id of the foreground media client (e.g. "com.apple.Music", "com.spotify.client").
    var clientBundleID: String?
    var isPlaying:    Bool = false

    /// True when there's any registered media client — even if paused. We surface
    /// the module while a track is loaded so the user can resume from the notch.
    var hasContent: Bool {
        if let t = title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let a = artist, !a.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let al = album, !al.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let d = artworkData, !d.isEmpty { return true }
        return false
    }

    var artworkImage: NSImage? {
        guard let data = artworkData, !data.isEmpty else { return nil }
        return NSImage(data: data)
    }
}
