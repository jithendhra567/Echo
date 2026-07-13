import AppKit
import CoreImage
import Foundation
import Observation

@Observable
@MainActor
final class CompanionController {
    private(set) var isEnabled = false
    private(set) var isListening = false
    private(set) var isPaired = false
    private(set) var pairedDeviceName: String?
    private(set) var statusText = "Off"
    private(set) var pairingQR: NSImage?
    private(set) var pairingURL: String = ""
    private(set) var lastError: String?

    /// Fired when a live clip arrives from the phone (updates Echo clipboard UI).
    var onRemoteClip: ((Clip, ClipStore.SaveResult) -> Void)?
    /// Fired after a bulk history merge (reload panel/history).
    var onHistoryChanged: (() -> Void)?

    private let server = CompanionServer()
    private let streamCapture = AppStreamCapture()
    private let inputInjector = RemoteInputInjector()

    private var pairingToken = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    private var store: ClipStore?
    private var monitor: ClipboardMonitor?
    private var suppressClipEcho = false
    private var clipObserver: NSObjectProtocol?

    var port: UInt16 { CompanionProtocol.defaultPort }

    func configure(store: ClipStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard !isEnabled else { return }
        isEnabled = true
        regenerateToken()
        refreshPairingPayload()
        wireServer()
        wireStream()
        server.start()
        statusText = "Waiting for phone…"
        lastError = nil
    }

    func stop() {
        isEnabled = false
        isPaired = false
        pairedDeviceName = nil
        statusText = "Off"
        Task { await streamCapture.stop() }
        inputInjector.clear()
        server.stop()
        pairingQR = nil
        pairingURL = ""
    }

    func rotateCode() {
        regenerateToken()
        refreshPairingPayload()
        if isPaired {
            // Force re-auth
            isPaired = false
            pairedDeviceName = nil
            statusText = "Waiting for phone…"
            server.stop()
            server.start()
        }
    }

    // MARK: - Wiring

    private func wireServer() {
        server.onListening = { [weak self] listening in
            Task { @MainActor in
                self?.isListening = listening
                if listening, self?.isPaired != true {
                    self?.statusText = "Waiting for phone…"
                }
            }
        }
        server.onClientDisconnected = { [weak self] in
            Task { @MainActor in
                self?.isPaired = false
                self?.pairedDeviceName = nil
                self?.statusText = self?.isEnabled == true ? "Waiting for phone…" : "Off"
                await self?.streamCapture.stop()
                self?.inputInjector.clear()
            }
        }
        server.onMessage = { [weak self] message in
            Task { @MainActor in
                await self?.handle(message)
            }
        }
    }

    private func wireStream() {
        streamCapture.onFrame = { [weak self] jpeg, width, height, bounds, windowID in
            guard let self, self.isPaired else { return }
            self.inputInjector.updateBounds(bounds)
            if self.inputInjector.targetWindowID != windowID,
               let bid = self.inputInjector.targetBundleId {
                self.inputInjector.setTarget(bundleId: bid, windowID: windowID, bounds: bounds)
            }
            let b64 = jpeg.base64EncodedString()
            self.server.send(.streamFrame(width: width, height: height, jpegBase64: b64))
        }
        streamCapture.onError = { [weak self] message in
            self?.lastError = message
            self?.server.send(.error(message: message))
        }
    }

    private func handle(_ message: CompanionMessage) async {
        switch message {
        case .hello(let token, let deviceName):
            guard token == pairingToken else {
                server.send(.error(message: "Invalid pairing token. Scan a fresh QR from Echo."))
                return
            }
            isPaired = true
            pairedDeviceName = deviceName
            statusText = "Connected · \(deviceName)"
            server.send(.helloOk(deviceId: UUID().uuidString, hostName: LocalNetworkInfo.hostDisplayName))
            await sendClipHistory()
            sendAppsList()

        case .clipPush(let dto):
            await ingestRemoteClip(dto, updatePasteboard: true)

        case .clipHistory(let clips):
            // Phone is merging — ingest its offline/local clips, then reply with full Mac history.
            await mergeRemoteClips(clips)
            await sendClipHistory()

        case .streamStart(let bundleId):
            guard isPaired else { return }
            await streamCapture.start(bundleId: bundleId)
            if streamCapture.windowID != 0 {
                inputInjector.setTarget(
                    bundleId: bundleId,
                    windowID: streamCapture.windowID,
                    bounds: streamCapture.windowBounds
                )
            }

        case .streamStop:
            await streamCapture.stop()
            inputInjector.clear()

        case .input(let event):
            guard isPaired else { return }
            inputInjector.handle(event)

        case .ping:
            server.send(.pong)

        case .helloOk, .appsList, .streamFrame, .error, .pong:
            break
        }
    }

    // MARK: - Clipboard

    func broadcastNewClip(_ clip: Clip) {
        guard isPaired, !suppressClipEcho else { return }
        let dto = CompanionClipDTO(clip: clip)
        if clip.contentType == .image && dto.contentBase64 == nil { return }
        server.send(.clipPush(clip: dto))
    }

    private func sendClipHistory() async {
        guard let store else { return }
        let clips = await store.fetchRecent(limit: 80)
        let dtos = clips.map(CompanionClipDTO.init)
        server.send(.clipHistory(clips: dtos))
    }

    private func mergeRemoteClips(_ dtos: [CompanionClipDTO]) async {
        guard let store else { return }
        var inserted = false
        for dto in dtos {
            guard let clip = dto.toClip() else { continue }
            let result = await store.save(clip)
            if case .inserted = result {
                inserted = true
            }
        }
        if inserted {
            onHistoryChanged?()
        }
    }

    private func ingestRemoteClip(_ dto: CompanionClipDTO, updatePasteboard: Bool) async {
        guard let store, let clip = dto.toClip() else { return }
        suppressClipEcho = true
        defer { suppressClipEcho = false }

        let result = await store.save(clip)
        // Always refresh Echo clipboard UI (panel / history).
        onRemoteClip?(clip, result)

        guard updatePasteboard else { return }
        monitor?.suppressNextCapture()
        switch clip.contentType {
        case .plainText, .url, .richText:
            if let text = clip.plainText ?? clip.resolvedPlainText {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        case .image:
            if let image = clip.image {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            }
        }
    }

    private func sendAppsList() {
        server.send(.appsList(apps: CompanionAppCatalog.runningApps()))
    }

    func refreshAppsForClient() {
        guard isPaired else { return }
        sendAppsList()
    }

    // MARK: - Pairing QR

    private func regenerateToken() {
        pairingToken = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    func refreshPairingPayload() {
        guard let host = LocalNetworkInfo.primaryIPv4Address() else {
            pairingURL = ""
            pairingQR = nil
            lastError = "No local network IP found. Join Wi‑Fi and try again."
            return
        }
        let payload = CompanionProtocol.PairingPayload(
            version: CompanionProtocol.version,
            host: host,
            port: port,
            token: pairingToken,
            hostName: LocalNetworkInfo.hostDisplayName
        )
        pairingURL = payload.urlString
        pairingQR = QRCodeImage.make(from: payload.urlString, dimension: 280)
        lastError = nil
    }
}

enum QRCodeImage {
    static func make(from string: String, dimension: CGFloat) -> NSImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator")
        else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = dimension / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
