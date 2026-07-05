import FirebaseRemoteConfig
import Observation
import SwiftUI

struct PromoConfig: Equatable {
    let enabled: Bool
    let id: String
    let text: String
    let linkText: String
    let linkURL: URL?
    let backgroundColor: Color

    static let disabled = PromoConfig(
        enabled: false,
        id: "",
        text: "",
        linkText: "Learn more",
        linkURL: nil,
        backgroundColor: Color.white.opacity(0.08)
    )
}

struct ForceUpdateConfig: Equatable {
    let title: String
    let message: String
    let buttonText: String
    let downloadURL: URL?
}

@Observable
@MainActor
final class RemoteConfigService {
    private(set) var isReady = false
    private(set) var promo = PromoConfig.disabled

    var minRequiredVersion: String { string("min_required_version", default: "1.0") }
    var latestVersion: String { string("latest_version", default: "1.0") }

    var forceUpdateConfig: ForceUpdateConfig {
        ForceUpdateConfig(
            title: string("force_update_title", default: "Update Required"),
            message: string("force_update_message", default: "Please update to continue using Echo."),
            buttonText: string("force_update_button_text", default: "Download Update"),
            downloadURL: url("update_download_url")
        )
    }

    private let remoteConfig: RemoteConfig
    private var configListener: ConfigUpdateListenerRegistration?

    init() {
        // AppDelegate creates this property before applicationDidFinishLaunching,
        // so Firebase must be configured here — not only in the delegate callback.
        FirebaseBootstrap.configure()
        remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        #if DEBUG
        settings.minimumFetchInterval = 3600
        #else
        settings.minimumFetchInterval = 43200
        #endif
        remoteConfig.configSettings = settings
        setDefaults()
    }

    func start() {
        configListener = remoteConfig.addOnConfigUpdateListener { [weak self] _, error in
            guard error == nil else { return }
            Task { @MainActor [weak self] in
                try? await self?.remoteConfig.activate()
                self?.refreshPromo()
            }
        }

        refreshPromo()
        isReady = true

        Task { await fetchAndActivate() }
    }

    func fetchAndActivate() async {
        let start = Date()
        do {
            _ = try await remoteConfig.fetchAndActivate()
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            AnalyticsService.logRemoteConfigFetch(success: true, durationMs: elapsed)
        } catch {
            AnalyticsService.logRemoteConfigFetch(success: false, durationMs: 0)
        }
        refreshPromo()
    }

    func refreshPromo() {
        let enabled = remoteConfig.configValue(forKey: "promo_enabled").boolValue
        let id = string("promo_id", default: "")
        let text = string("promo_text", default: "")
        let linkText = string("promo_link_text", default: "Learn more")
        let linkURL = url("promo_link_url")
        let hex = string("promo_background_color", default: "#FFFFFF14")

        promo = PromoConfig(
            enabled: enabled && !id.isEmpty && !text.isEmpty,
            id: id,
            text: text,
            linkText: linkText,
            linkURL: linkURL,
            backgroundColor: Self.color(fromHex: hex)
        )
    }

    // MARK: - Defaults

    private func setDefaults() {
        remoteConfig.setDefaults([
            "min_required_version": "1.0" as NSObject,
            "latest_version": "1.0" as NSObject,
            "force_update_title": "Update Required" as NSObject,
            "force_update_message": "Please update to continue using Echo." as NSObject,
            "force_update_button_text": "Download Update" as NSObject,
            "update_download_url": "" as NSObject,
            "promo_enabled": false as NSObject,
            "promo_id": "" as NSObject,
            "promo_text": "" as NSObject,
            "promo_link_text": "Learn more" as NSObject,
            "promo_link_url": "" as NSObject,
            "promo_background_color": "#FFFFFF14" as NSObject,
        ])
    }

    // MARK: - Accessors

    private func string(_ key: String, default defaultValue: String) -> String {
        let value = remoteConfig.configValue(forKey: key).stringValue
        return value.isEmpty ? defaultValue : value
    }

    private func url(_ key: String) -> URL? {
        let value = remoteConfig.configValue(forKey: key).stringValue
        guard !value.isEmpty, let url = URL(string: value) else { return nil }
        return url
    }

    static func color(fromHex hex: String) -> Color {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }

        guard sanitized.count == 6 || sanitized.count == 8,
              let value = UInt64(sanitized, radix: 16)
        else { return Color.white.opacity(0.08) }

        let r, g, b, a: Double
        if sanitized.count == 8 {
            r = Double((value & 0xFF00_0000) >> 24) / 255
            g = Double((value & 0x00FF_0000) >> 16) / 255
            b = Double((value & 0x0000_FF00) >> 8) / 255
            a = Double(value & 0x0000_00FF) / 255
        } else {
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
            a = 1
        }
        return Color(red: r, green: g, blue: b, opacity: a)
    }
}
