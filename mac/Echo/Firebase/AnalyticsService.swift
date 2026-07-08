import FirebaseAnalytics
import Foundation

enum AnalyticsService {
    // MARK: - Lifecycle & updates

    static func logAppLaunch() {
        log("app_launch", [
            "app_version": AppVersion.marketing,
            "build_number": AppVersion.build,
        ])
    }

    static func logAppQuit(sessionDurationSec: Int) {
        log("app_quit", ["session_duration_sec": sessionDurationSec])
    }

    static func logRemoteConfigFetch(success: Bool, durationMs: Int) {
        log("remote_config_fetch", [
            "success": success,
            "duration_ms": durationMs,
        ])
    }

    static func logForceUpdateShown(current: String, required: String) {
        log("force_update_shown", [
            "current_version": current,
            "required_version": required,
        ])
    }

    static func logForceUpdateClicked() {
        log("force_update_clicked")
    }

    static func logSoftUpdateAvailable(current: String, latest: String) {
        log("soft_update_available", [
            "current_version": current,
            "latest_version": latest,
        ])
    }

    static func logUpdateCheckResult(outcome: String) {
        log("update_check_result", ["outcome": outcome])
    }

    // MARK: - Promo

    static func logPromoImpression(promoID: String) {
        log("promo_impression", ["promo_id": promoID])
    }

    static func logPromoClick(promoID: String, linkURL: String) {
        log("promo_click", [
            "promo_id": promoID,
            "link_url": linkURL,
        ])
    }

    static func logPromoDismiss(promoID: String) {
        log("promo_dismiss", ["promo_id": promoID])
    }

    // MARK: - Launcher

    static func logLauncherOpened() {
        log("launcher_opened")
    }

    static func logLauncherClosed() {
        log("launcher_closed")
    }

    static func logLauncherPanelSwitched(panel: String) {
        log("launcher_panel_switched", ["panel": panel])
    }

    static func logLauncherTabsInSearchChanged(enabled: Bool) {
        log("launcher_tabs_in_search_changed", ["enabled": enabled])
    }

    static func logSearchQuery(length: Int) {
        log("search_query", ["query_length_bucket": queryLengthBucket(length)])
    }

    static func logAppLaunchedFromLauncher(bundleID: String?, appName: String) {
        log("app_launched_from_launcher", [
            "bundle_id": bundleID ?? "unknown",
            "app_name": appName,
        ])
    }

    static func logTabOpenedFromLauncher(tabType: String, browser: String, source: String) {
        log("tab_opened_from_launcher", [
            "tab_type": tabType,
            "browser": browser,
            "source": source,
        ])
    }

    static func logGoogleSearchOpened() {
        log("google_search_opened")
    }

    static func logDomainOpened() {
        log("domain_opened")
    }

    static func logInstantSearchOpened() {
        log("instant_search_opened")
    }

    static func logInstantSearchClosed() {
        log("instant_search_closed")
    }

    static func logUtilityResultShown(kind: String) {
        log("utility_result_shown", ["kind": kind])
    }

    static func logUtilityResultCopied(kind: String) {
        log("utility_result_copied", ["kind": kind])
    }

    // MARK: - Clipboard

    static func logClipCaptured(contentType: String, isDuplicate: Bool) {
        log("clip_captured", [
            "content_type": contentType,
            "is_duplicate": isDuplicate,
        ])
    }

    static func logClipCopied(contentType: String, surface: String, pasteMode: String = "default") {
        log("clip_copied", [
            "content_type": contentType,
            "surface": surface,
            "paste_mode": pasteMode,
        ])
    }

    static func logClipPinned(action: String, contentType: String, surface: String) {
        log("clip_pinned", [
            "action": action,
            "content_type": contentType,
            "surface": surface,
        ])
    }

    static func logClipDeleted(contentType: String, surface: String) {
        log("clip_deleted", [
            "content_type": contentType,
            "surface": surface,
        ])
    }

    static func logClipboardHistoryCleared(includePinned: Bool, surface: String) {
        log("clipboard_history_cleared", [
            "include_pinned": includePinned,
            "surface": surface,
        ])
    }

    static func logClipDragStarted(contentType: String) {
        log("clip_drag_started", ["content_type": contentType])
    }

    static func logClipDragCompleted(contentType: String, outcome: String) {
        log("clip_drag_completed", [
            "content_type": contentType,
            "outcome": outcome,
        ])
    }

    static func logClipboardPanelOpened() {
        log("clipboard_panel_opened")
    }

    static func logClipboardPanelClosed() {
        log("clipboard_panel_closed")
    }

    static func logPasteModeChanged(enabled: Bool) {
        log("paste_mode_changed", ["enabled": enabled])
    }

    // MARK: - Dashboard & settings

    static func logDashboardOpened(source: String, section: String) {
        log("dashboard_opened", [
            "source": source,
            "section": section,
        ])
    }

    static func logLaunchAtLoginChanged(enabled: Bool) {
        log("launch_at_login_changed", ["enabled": enabled])
    }

    static func logRetentionDaysChanged(days: Int) {
        log("retention_days_changed", ["days": days])
    }

    static func logClipboardPausedChanged(paused: Bool) {
        log("clipboard_paused_changed", ["paused": paused])
    }

    static func logCaptureImagesChanged(enabled: Bool) {
        log("capture_images_changed", ["enabled": enabled])
    }

    static func logHotkeyChanged(target: String) {
        log("hotkey_changed", ["target": target])
    }

    // MARK: - Onboarding

    static func logOnboardingShown(source: String = "first_launch") {
        log("onboarding_shown", ["source": source])
    }

    static func logOnboardingReplayed() {
        log("onboarding_replayed")
    }

    static func logOnboardingSkipped() {
        log("onboarding_skipped")
    }

    static func logOnboardingCompleted(step: Int) {
        log("onboarding_completed", ["last_step": step])
    }

    static func logOnboardingTryLauncher() {
        log("onboarding_try_launcher")
    }

    // MARK: - Notch

    static func logNotchOpened(trigger: String) {
        log("notch_opened", ["trigger": trigger])
    }

    static func logNotchClosed(trigger: String) {
        log("notch_closed", ["trigger": trigger])
    }

    static func logNotchModuleShown(module: String) {
        log("notch_module_shown", ["module": module])
    }

    static func logMirrorRevealed() {
        log("mirror_revealed")
    }

    static func logMirrorHidden() {
        log("mirror_hidden")
    }

    static func logMirrorCameraStarted(outcome: String) {
        log("mirror_camera_started", ["outcome": outcome])
    }

    static func logSystemFileDragDetected() {
        log("system_file_drag_detected")
    }

    static func logTrayFileDropped(fileCount: Int, importMode: String, dropKind: String) {
        log("tray_file_dropped", [
            "file_count": fileCount,
            "import_mode": importMode,
            "drop_kind": dropKind,
        ])
    }

    static func logTrayFileRemoved(remainingCount: Int) {
        log("tray_file_removed", ["remaining_count": remainingCount])
    }

    static func logTrayCleared(fileCount: Int) {
        log("tray_cleared", ["file_count": fileCount])
    }

    static func logTrayDragOutStarted(fileCount: Int) {
        log("tray_drag_out_started", ["file_count": fileCount])
    }

    static func logTrayDragOutCompleted(fileCount: Int, outcome: String) {
        log("tray_drag_out_completed", [
            "file_count": fileCount,
            "outcome": outcome,
        ])
    }

    // MARK: - Private

    private static func log(_ name: String, _ params: [String: Any] = [:]) {
        Analytics.logEvent(name, parameters: params.isEmpty ? nil : params)
    }

    private static func queryLengthBucket(_ length: Int) -> String {
        switch length {
        case 0: return "0"
        case 1...5: return "1-5"
        case 6...20: return "6-20"
        default: return "21+"
        }
    }
}
