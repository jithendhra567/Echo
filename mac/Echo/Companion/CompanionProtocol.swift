import AppKit
import Foundation

/// Wire protocol for Echo Mac ↔ Android companion over local WebSocket.
nonisolated enum CompanionProtocol {
    static let version = 1
    static let defaultPort: UInt16 = 8742
    static let urlScheme = "echo"

    /// QR / deep-link payload: `echo://pair?v=1&host=…&port=8742&token=…&name=…`
    struct PairingPayload: Sendable, Equatable {
        var version: Int
        var host: String
        var port: UInt16
        var token: String
        var hostName: String

        var urlString: String {
            var components = URLComponents()
            components.scheme = CompanionProtocol.urlScheme
            components.host = "pair"
            components.queryItems = [
                URLQueryItem(name: "v", value: "\(version)"),
                URLQueryItem(name: "host", value: host),
                URLQueryItem(name: "port", value: "\(port)"),
                URLQueryItem(name: "token", value: token),
                URLQueryItem(name: "name", value: hostName),
            ]
            return components.url?.absoluteString
                ?? "\(CompanionProtocol.urlScheme)://pair?v=\(version)&host=\(host)&port=\(port)&token=\(token)"
        }

        static func parse(_ string: String) -> PairingPayload? {
            guard let url = URL(string: string),
                  url.scheme == CompanionProtocol.urlScheme,
                  url.host == "pair" || url.path.contains("pair")
            else { return nil }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? {
                items.first(where: { $0.name == name })?.value
            }
            guard let host = value("host"),
                  let portStr = value("port"), let port = UInt16(portStr),
                  let token = value("token"), !token.isEmpty
            else { return nil }
            let version = Int(value("v") ?? "1") ?? 1
            let name = value("name") ?? "Mac"
            return PairingPayload(version: version, host: host, port: port, token: token, hostName: name)
        }
    }
}

// MARK: - DTOs

nonisolated struct CompanionClipDTO: Codable, Sendable, Identifiable {
    var id: String
    var contentType: String
    var text: String?
    var contentBase64: String?
    var sourceAppName: String?
    var sourceAppBundle: String?
    var windowTitle: String?
    var createdAt: Double
    var isPinned: Bool

    @MainActor
    init(clip: Clip) {
        id = clip.id.uuidString
        contentType = clip.contentType.rawValue
        sourceAppName = clip.sourceAppName
        sourceAppBundle = clip.sourceAppBundle
        windowTitle = clip.windowTitle
        createdAt = clip.createdAt.timeIntervalSince1970
        isPinned = clip.isPinned
        switch clip.contentType {
        case .plainText, .url:
            text = clip.plainText
            contentBase64 = nil
        case .richText:
            text = clip.resolvedPlainText
            if clip.contentData.count <= 256 * 1024 {
                contentBase64 = clip.contentData.base64EncodedString()
            } else {
                contentBase64 = nil
            }
        case .image:
            text = nil
            if clip.contentData.count <= 512 * 1024 {
                contentBase64 = clip.contentData.base64EncodedString()
            } else if let jpeg = CompanionClipDTO.compressedJPEG(from: clip.contentData, maxBytes: 400_000) {
                contentBase64 = jpeg.base64EncodedString()
            } else {
                contentBase64 = nil
            }
        }
    }

    @MainActor
    func toClip() -> Clip? {
        let uuid = UUID(uuidString: id) ?? UUID()
        let type = ClipContentType(rawValue: contentType) ?? .plainText
        let data: Data
        switch type {
        case .plainText, .url:
            guard let text else { return nil }
            data = Data(text.utf8)
        case .richText:
            if let contentBase64, let decoded = Data(base64Encoded: contentBase64) {
                data = decoded
            } else if let text {
                data = Data(text.utf8)
            } else {
                return nil
            }
        case .image:
            guard let contentBase64, let decoded = Data(base64Encoded: contentBase64) else { return nil }
            data = decoded
        }
        return Clip(
            id: uuid,
            contentData: data,
            contentType: type == .richText && contentBase64 == nil ? .plainText : type,
            sourceAppBundle: sourceAppBundle,
            sourceAppName: sourceAppName ?? "Android",
            windowTitle: windowTitle,
            createdAt: Date(timeIntervalSince1970: createdAt),
            isPinned: isPinned
        )
    }

    @MainActor
    private static func compressedJPEG(from data: Data, maxBytes: Int) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        var quality: CGFloat = 0.7
        while quality >= 0.2 {
            if let jpeg = image.jpegData(compressionQuality: quality), jpeg.count <= maxBytes {
                return jpeg
            }
            quality -= 0.15
        }
        return image.jpegData(compressionQuality: 0.2)
    }
}

nonisolated struct CompanionAppDTO: Codable, Sendable, Identifiable {
    var id: String { bundleId }
    var bundleId: String
    var name: String
    var isRunning: Bool
    var iconBase64: String?
}

nonisolated struct CompanionInputEvent: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case tap, move, down, up, scroll, key
    }
    var kind: Kind
    /// Normalized 0…1 relative to the streamed window.
    var x: Double?
    var y: Double?
    var dx: Double?
    var dy: Double?
    var key: String?
    var modifiers: [String]?
}

nonisolated enum CompanionMessage: Codable, Sendable {
    case hello(token: String, deviceName: String)
    case helloOk(deviceId: String, hostName: String)
    case clipHistory(clips: [CompanionClipDTO])
    case clipPush(clip: CompanionClipDTO)
    case appsList(apps: [CompanionAppDTO])
    case streamStart(bundleId: String)
    case streamFrame(width: Int, height: Int, jpegBase64: String)
    case streamStop
    case input(CompanionInputEvent)
    case error(message: String)
    case ping
    case pong

    private enum CodingKeys: String, CodingKey {
        case type, token, deviceName, deviceId, hostName, clips, clip, apps, bundleId
        case width, height, data, kind, x, y, dx, dy, key, modifiers, message
    }

    private enum TypeValue: String, Codable {
        case hello, hello_ok, clip_history, clip_push, apps_list
        case stream_start, stream_frame, stream_stop, input, error, ping, pong
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(TypeValue.self, forKey: .type)
        switch type {
        case .hello:
            self = .hello(
                token: try c.decode(String.self, forKey: .token),
                deviceName: try c.decodeIfPresent(String.self, forKey: .deviceName) ?? "Android"
            )
        case .hello_ok:
            self = .helloOk(
                deviceId: try c.decode(String.self, forKey: .deviceId),
                hostName: try c.decode(String.self, forKey: .hostName)
            )
        case .clip_history:
            self = .clipHistory(clips: try c.decode([CompanionClipDTO].self, forKey: .clips))
        case .clip_push:
            self = .clipPush(clip: try c.decode(CompanionClipDTO.self, forKey: .clip))
        case .apps_list:
            self = .appsList(apps: try c.decode([CompanionAppDTO].self, forKey: .apps))
        case .stream_start:
            self = .streamStart(bundleId: try c.decode(String.self, forKey: .bundleId))
        case .stream_frame:
            self = .streamFrame(
                width: try c.decode(Int.self, forKey: .width),
                height: try c.decode(Int.self, forKey: .height),
                jpegBase64: try c.decode(String.self, forKey: .data)
            )
        case .stream_stop:
            self = .streamStop
        case .input:
            self = .input(CompanionInputEvent(
                kind: try c.decode(CompanionInputEvent.Kind.self, forKey: .kind),
                x: try c.decodeIfPresent(Double.self, forKey: .x),
                y: try c.decodeIfPresent(Double.self, forKey: .y),
                dx: try c.decodeIfPresent(Double.self, forKey: .dx),
                dy: try c.decodeIfPresent(Double.self, forKey: .dy),
                key: try c.decodeIfPresent(String.self, forKey: .key),
                modifiers: try c.decodeIfPresent([String].self, forKey: .modifiers)
            ))
        case .error:
            self = .error(message: try c.decode(String.self, forKey: .message))
        case .ping:
            self = .ping
        case .pong:
            self = .pong
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hello(let token, let deviceName):
            try c.encode(TypeValue.hello, forKey: .type)
            try c.encode(token, forKey: .token)
            try c.encode(deviceName, forKey: .deviceName)
        case .helloOk(let deviceId, let hostName):
            try c.encode(TypeValue.hello_ok, forKey: .type)
            try c.encode(deviceId, forKey: .deviceId)
            try c.encode(hostName, forKey: .hostName)
        case .clipHistory(let clips):
            try c.encode(TypeValue.clip_history, forKey: .type)
            try c.encode(clips, forKey: .clips)
        case .clipPush(let clip):
            try c.encode(TypeValue.clip_push, forKey: .type)
            try c.encode(clip, forKey: .clip)
        case .appsList(let apps):
            try c.encode(TypeValue.apps_list, forKey: .type)
            try c.encode(apps, forKey: .apps)
        case .streamStart(let bundleId):
            try c.encode(TypeValue.stream_start, forKey: .type)
            try c.encode(bundleId, forKey: .bundleId)
        case .streamFrame(let width, let height, let data):
            try c.encode(TypeValue.stream_frame, forKey: .type)
            try c.encode(width, forKey: .width)
            try c.encode(height, forKey: .height)
            try c.encode(data, forKey: .data)
        case .streamStop:
            try c.encode(TypeValue.stream_stop, forKey: .type)
        case .input(let event):
            try c.encode(TypeValue.input, forKey: .type)
            try c.encode(event.kind, forKey: .kind)
            try c.encodeIfPresent(event.x, forKey: .x)
            try c.encodeIfPresent(event.y, forKey: .y)
            try c.encodeIfPresent(event.dx, forKey: .dx)
            try c.encodeIfPresent(event.dy, forKey: .dy)
            try c.encodeIfPresent(event.key, forKey: .key)
            try c.encodeIfPresent(event.modifiers, forKey: .modifiers)
        case .error(let message):
            try c.encode(TypeValue.error, forKey: .type)
            try c.encode(message, forKey: .message)
        case .ping:
            try c.encode(TypeValue.ping, forKey: .type)
        case .pong:
            try c.encode(TypeValue.pong, forKey: .type)
        }
    }
}

private extension NSImage {
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}
