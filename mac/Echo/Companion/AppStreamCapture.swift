import AppKit
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Captures a single app window for phone streaming.
/// Prefers ScreenCaptureKit screenshots; falls back to CGWindowList (via dlsym)
/// when SCK returns empty/black frames for covered background windows.
@MainActor
final class AppStreamCapture: NSObject {
    var onFrame: ((Data, Int, Int, CGRect, CGWindowID) -> Void)?
    var onError: ((String) -> Void)?

    private var targetBundleId: String?
    private var targetPID: pid_t = 0
    private(set) var windowID: CGWindowID = 0
    private(set) var windowBounds: CGRect = .zero

    private let maxWidth = 1280
    private let jpegQuality: CGFloat = 0.55
    private var captureTask: Task<Void, Never>?
    private let captureInterval: Duration = .milliseconds(100)
    private var consecutiveDarkFrames = 0

    func start(bundleId: String) async {
        await stop()
        targetBundleId = bundleId

        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }),
              app.processIdentifier > 0
        else {
            onError?("App is not running.")
            return
        }
        targetPID = app.processIdentifier

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let windows = content.windows
                .filter {
                    $0.owningApplication?.bundleIdentifier == bundleId
                        && $0.frame.width > 40
                        && $0.frame.height > 40
                }
                .sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
            guard let window = windows.first else {
                // Fall back to CG window list (includes some off-screen cases SCK omits).
                guard let resolved = Self.resolveCGWindow(pid: targetPID) else {
                    onError?("No window found for this app. Open a window and try again.")
                    return
                }
                windowID = resolved.id
                windowBounds = resolved.bounds
                beginLoop(preferLegacySnapshot: true)
                return
            }
            windowID = window.windowID
            windowBounds = window.frame
        } catch {
            guard let resolved = Self.resolveCGWindow(pid: targetPID) else {
                onError?(error.localizedDescription)
                return
            }
            windowID = resolved.id
            windowBounds = resolved.bounds
        }

        // Bring windows into the compositor once so the first frames aren't empty
        // (Xcode / Metal apps often stop drawing while fully covered).
        app.unhide()
        app.activate(options: [.activateAllWindows])

        beginLoop(preferLegacySnapshot: false)
    }

    func stop() async {
        captureTask?.cancel()
        captureTask = nil
        targetBundleId = nil
        targetPID = 0
        windowID = 0
        windowBounds = .zero
        consecutiveDarkFrames = 0
    }

    private func beginLoop(preferLegacySnapshot: Bool) {
        var useLegacy = preferLegacySnapshot
        captureTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let usedLegacy = await self.captureOnce(forceLegacy: useLegacy)
                if usedLegacy {
                    useLegacy = true
                }
                try? await Task.sleep(for: self.captureInterval)
            }
        }
    }

    /// Returns `true` when the legacy CG path was used for this frame.
    @discardableResult
    private func captureOnce(forceLegacy: Bool) async -> Bool {
        guard windowID != 0 else { return forceLegacy }

        if let resolved = Self.resolveCGWindow(pid: targetPID) {
            windowID = resolved.id
            windowBounds = resolved.bounds
        }

        let id = windowID
        let bounds = windowBounds
        let maxWidth = self.maxWidth
        let quality = self.jpegQuality
        let bundleId = targetBundleId

        if !forceLegacy, let bundleId {
            if let frame = await Self.sckSnapshotJPEG(
                bundleId: bundleId,
                windowID: id,
                maxWidth: maxWidth,
                quality: quality
            ) {
                if Self.isMostlyDark(frame.data) {
                    consecutiveDarkFrames += 1
                    if consecutiveDarkFrames >= 3 {
                        // Covered / not compositing — switch to window-server snapshot.
                        if let legacy = await Self.legacySnapshotJPEG(
                            windowID: id, maxWidth: maxWidth, quality: quality
                        ) {
                            consecutiveDarkFrames = 0
                            onFrame?(legacy.data, legacy.width, legacy.height, bounds, id)
                            return true
                        }
                        // Nudge the app awake so SCK can get pixels again.
                        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
                            .first?
                            .activate(options: [.activateAllWindows])
                    }
                } else {
                    consecutiveDarkFrames = 0
                }
                onFrame?(frame.data, frame.width, frame.height, bounds, id)
                return false
            }
        }

        if let legacy = await Self.legacySnapshotJPEG(
            windowID: id, maxWidth: maxWidth, quality: quality
        ) {
            consecutiveDarkFrames = 0
            onFrame?(legacy.data, legacy.width, legacy.height, bounds, id)
            return true
        }
        return forceLegacy
    }

    // MARK: - SCK screenshot

    nonisolated private static func sckSnapshotJPEG(
        bundleId: String,
        windowID: CGWindowID,
        maxWidth: Int,
        quality: CGFloat
    ) async -> (data: Data, width: Int, height: Int)? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let window = content.windows.first(where: { $0.windowID == windowID })
                ?? content.windows
                    .filter { $0.owningApplication?.bundleIdentifier == bundleId && $0.frame.width > 40 }
                    .sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
                    .first
            guard let window else { return nil }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = min(1.0, CGFloat(maxWidth) / max(window.frame.width, 1))
            config.width = max(2, Int(window.frame.width * scale) & ~1)
            config.height = max(2, Int(window.frame.height * scale) & ~1)
            config.showsCursor = false
            config.pixelFormat = kCVPixelFormatType_32BGRA

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            guard let data = jpegData(from: image, quality: quality) else { return nil }
            return (data, image.width, image.height)
        } catch {
            return nil
        }
    }

    // MARK: - Legacy CG snapshot (occluded windows)

    private typealias CGWindowListCreateImageFn = @convention(c) (
        CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption
    ) -> Unmanaged<CGImage>?

    nonisolated private static let cgWindowListCreateImage: CGWindowListCreateImageFn? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let sym = dlsym(handle, "CGWindowListCreateImage")
        else { return nil }
        return unsafeBitCast(sym, to: CGWindowListCreateImageFn.self)
    }()

    nonisolated private static func legacySnapshotJPEG(
        windowID: CGWindowID,
        maxWidth: Int,
        quality: CGFloat
    ) async -> (data: Data, width: Int, height: Int)? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let fn = cgWindowListCreateImage,
                      let unmanaged = fn(
                        .null,
                        .optionIncludingWindow,
                        windowID,
                        [.boundsIgnoreFraming, .bestResolution]
                      )
                else {
                    continuation.resume(returning: nil)
                    return
                }
                let image = unmanaged.takeRetainedValue()
                let scaled = scaledImage(image, maxWidth: maxWidth) ?? image
                let data = jpegData(from: scaled, quality: quality)
                if let data {
                    continuation.resume(returning: (data, scaled.width, scaled.height))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Window list

    private struct ResolvedWindow: Sendable {
        var id: CGWindowID
        var bounds: CGRect
    }

    nonisolated private static func resolveCGWindow(pid: pid_t) -> ResolvedWindow? {
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        var best: (ResolvedWindow, CGFloat, Bool)?
        for entry in info {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else { continue }
            guard let number = entry[kCGWindowNumber as String] as? NSNumber else { continue }
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  rect.width > 40, rect.height > 40
            else { continue }
            let onScreen = entry[kCGWindowIsOnscreen as String] as? Bool ?? false
            let area = rect.width * rect.height
            let candidate = ResolvedWindow(id: CGWindowID(number.uint32Value), bounds: rect)
            if let current = best {
                if onScreen != current.2 {
                    if onScreen { best = (candidate, area, onScreen) }
                } else if area > current.1 {
                    best = (candidate, area, onScreen)
                }
            } else {
                best = (candidate, area, onScreen)
            }
        }
        return best?.0
    }

    // MARK: - Image helpers

    nonisolated private static func isMostlyDark(_ jpeg: Data) -> Bool {
        // Cheap heuristic: tiny / nearly-empty payloads, or decode and sample luminance.
        if jpeg.count < 2_500 { return true }
        guard let image = NSImage(data: jpeg)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return true
        }
        let w = image.width
        let h = image.height
        guard w > 8, h > 8 else { return true }
        guard let ctx = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
        guard let data = ctx.data else { return false }
        let ptr = data.bindMemory(to: UInt8.self, capacity: 8 * 8 * 4)
        var sum = 0
        for i in 0..<(8 * 8) {
            let o = i * 4
            sum += Int(ptr[o]) + Int(ptr[o + 1]) + Int(ptr[o + 2])
        }
        let avg = Double(sum) / Double(8 * 8 * 3)
        return avg < 12 // nearly black
    }

    nonisolated private static func scaledImage(_ image: CGImage, maxWidth: Int) -> CGImage? {
        let w = image.width
        let h = image.height
        guard w > maxWidth else { return image }
        let scale = CGFloat(maxWidth) / CGFloat(w)
        let newW = maxWidth
        let newH = max(1, Int(CGFloat(h) * scale))
        guard let ctx = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage()
    }

    nonisolated private static func jpegData(from image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, image, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
