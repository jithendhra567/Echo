import AppKit
import Sparkle

@MainActor
final class SparkleUpdaterController: NSObject {
    private var updaterController: SPUStandardUpdaterController?

    func start() {
        guard updaterController == nil else { return }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}

extension SparkleUpdaterController: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        Task { @MainActor in
            if let error {
                AnalyticsService.logUpdateCheckResult(outcome: "error: \(error.localizedDescription)")
            } else {
                AnalyticsService.logUpdateCheckResult(outcome: "completed")
            }
        }
    }
}
