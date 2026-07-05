import Foundation

enum UpdateDecision: Equatable {
    case none
    case softUpdate(latest: String)
    case forceUpdate(required: String)
}

enum UpdateManager {
    static func evaluate(remoteConfig: RemoteConfigService) -> UpdateDecision {
        let current = AppVersion.marketing

        if AppVersion.isLessThan(current, than: remoteConfig.minRequiredVersion) {
            return .forceUpdate(required: remoteConfig.minRequiredVersion)
        }

        if AppVersion.isLessThan(current, than: remoteConfig.latestVersion) {
            return .softUpdate(latest: remoteConfig.latestVersion)
        }

        return .none
    }
}
