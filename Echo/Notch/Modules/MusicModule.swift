import AppKit
import Observation
import SwiftUI

/// Now-Playing module driven by the system's MediaRemote framework.
@Observable
@MainActor
final class MusicModule: NotchModule {

    let id           = "music"
    let title        = "Music"
    let iconName     = "music.note"
    let supportsDrop = false

    /// Surface the module any time there's metadata loaded — playing or paused.
    var isActive: Bool { bridge.info.hasContent }

    let bridge: MediaRemoteBridge

    init(bridge: MediaRemoteBridge) {
        self.bridge = bridge
    }

    var closedLeft:   AnyView { AnyView(MusicClosedLeft(module: self)) }
    var closedRight:  AnyView { AnyView(MusicClosedRight(module: self)) }
    var closedCenter: AnyView { AnyView(MusicClosedCenter(module: self)) }
    var openView:     AnyView { AnyView(MusicOpenView(module: self)) }
}

// MARK: - Closed pill fragments

private struct MusicClosedLeft: View {
    let module: MusicModule
    var body: some View {
        Group {
            if let art = module.bridge.info.artworkImage {
                Image(nsImage: art)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
}

private struct MusicClosedCenter: View {
    let module: MusicModule
    var body: some View {
        if let title = module.bridge.info.title {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 200)
        } else {
            EmptyView()
        }
    }
}

private struct MusicClosedRight: View {
    let module: MusicModule
    var body: some View {
        Group {
            if module.bridge.info.isPlaying {
                PlayingBars()
            } else {
                Image(systemName: "pause.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }
}

private struct PlayingBars: View {
    var body: some View {
        // 12 Hz is plenty for three little bars — the eye can't tell the
        // difference between this and 24 Hz but the cost halves.
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = Double(i) * 0.5
                    let h = 4 + 8 * abs(sin(t * 3 + phase))
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 2.5, height: CGFloat(h))
                }
            }
            .frame(height: 14)
        }
    }
}

// MARK: - Open view (mini-player)

private struct MusicOpenView: View {
    let module: MusicModule

    var body: some View {
        let info = module.bridge.info
        HStack(alignment: .center, spacing: 14) {
            artwork(info: info)

            VStack(alignment: .leading, spacing: 3) {
                Text(info.title ?? "Nothing playing")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(info.artist ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                scrubber(info: info)
                controls(info: info)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func artwork(info: NowPlayingInfo) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
            if let img = info.artworkImage {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(width: 90, height: 90)
        .shadow(color: .black.opacity(0.5), radius: 5, y: 2)
    }

    @ViewBuilder
    private func scrubber(info: NowPlayingInfo) -> some View {
        let progress: Double = {
            guard let d = info.duration, d > 0, let e = info.elapsedTime else { return 0 }
            return min(1, max(0, e / d))
        }()
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 3)
    }

    @ViewBuilder
    private func controls(info: NowPlayingInfo) -> some View {
        HStack(spacing: 22) {
            Spacer(minLength: 0)
            iconButton(systemName: "backward.fill", size: 15) { module.bridge.previousTrack() }
            iconButton(
                systemName: info.isPlaying ? "pause.fill" : "play.fill",
                size: 19
            ) { module.bridge.togglePlayPause() }
            iconButton(systemName: "forward.fill", size: 15) { module.bridge.nextTrack() }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func iconButton(systemName: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: size + 10, height: size + 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
