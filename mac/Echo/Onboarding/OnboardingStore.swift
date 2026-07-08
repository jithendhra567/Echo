import Foundation

/// First-launch onboarding state. Shown once; skippable at any step.
enum OnboardingStore {
    private static let completedKey = "echo.onboarding.completed"
    private static let legacyMigratedKey = "echo.onboarding.legacy_migrated"

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    static func resetCompleted() {
        UserDefaults.standard.set(false, forKey: completedKey)
    }

    /// Skips onboarding for users who already used Echo before this flow existed.
    static func migrateLegacyUserIfNeeded(store: ClipStore) async {
        guard !isCompleted else { return }
        guard !UserDefaults.standard.bool(forKey: legacyMigratedKey) else { return }
        UserDefaults.standard.set(true, forKey: legacyMigratedKey)

        let hasCustomHotkeys =
            UserDefaults.standard.object(forKey: "launcher_hotkey_keycode") != nil
            || UserDefaults.standard.object(forKey: "clipboard_hotkey_keycode") != nil

        let clips = await store.fetchRecent(limit: 1)
        if hasCustomHotkeys || !clips.isEmpty {
            markCompleted()
        }
    }

    static func shouldPresent() -> Bool {
        !isCompleted
    }
}
