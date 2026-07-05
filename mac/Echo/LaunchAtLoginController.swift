import Observation
import ServiceManagement

/// Launch at login via `SMAppService.mainApp` (macOS 13+). User can also manage the item in
/// System Settings → General → Login Items & Extensions.
@Observable
@MainActor
final class LaunchAtLoginController {
    /// Incremented when login-item status may have changed so SwiftUI re-reads `isOpenAtLoginEnabled`.
    private(set) var refreshTrigger = 0

    var isOpenAtLoginEnabled: Bool {
        _ = refreshTrigger
        return SMAppService.mainApp.status == .enabled
    }

    var lastErrorMessage: String?

    func refreshStatus() {
        refreshTrigger &+= 1
    }

    func setOpenAtLogin(_ enabled: Bool) {
        lastErrorMessage = nil
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            AnalyticsService.logLaunchAtLoginChanged(enabled: enabled)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        refreshTrigger &+= 1
    }
}
