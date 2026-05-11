import AppKit
import Observation

/// State + module owner for the notch panel. Modeled directly on boring.notch's
/// `BoringViewModel`: just two states (closed/open) and a single active module
/// chosen by priority.
@Observable
@MainActor
final class NotchViewModel {

    enum NotchState: Equatable {
        case closed
        case open
    }

    // MARK: - Modules

    let tray:   TrayModule
    let music:  MusicModule
    let bridge: MediaRemoteBridge

    var modules: [any NotchModule] { [tray, music] }

    // MARK: - State

    /// Whether the pill is visually expanded.
    var notchState: NotchState = .closed
    /// Tracked separately so we can fade non-interactive overlays.
    var isHovering: Bool = false
    /// User explicitly picked a tab in the open view (cleared on close).
    var userSelectedModuleID: String?

    /// Notch metrics for the current screen.
    var closedNotchSize: CGSize = .init(width: 185, height: 32)

    // MARK: - Init

    init() {
        let bridge = MediaRemoteBridge()
        self.bridge = bridge
        self.tray   = TrayModule()
        self.music  = MusicModule(bridge: bridge)
    }

    func start() {
        bridge.start()
        // Music notifications already update bridge.info via the bridge itself;
        // SwiftUI re-renders automatically because views observe it. No extra
        // plumbing needed — modules expose `isActive` derived from bridge state.
    }

    // MARK: - Active module priority

    /// Priority:
    /// 1. Drag in progress → Tray (forced).
    /// 2. While open and the user picked a tab → that module.
    /// 3. First module whose `isActive == true`.
    /// 4. Default to Tray.
    var activeModule: any NotchModule {
        if tray.isDragInFlight {
            return tray
        }
        if notchState == .open,
           let id = userSelectedModuleID,
           let m = modules.first(where: { $0.id == id })
        {
            return m
        }
        if let m = modules.first(where: { $0.isActive }) {
            return m
        }
        return tray
    }

    /// True when any module wants to surface itself in the closed pill.
    var anyModuleActive: Bool { modules.contains { $0.isActive } }

    // MARK: - Actions

    // Idempotent — these are called repeatedly from drag callbacks and hover
    // events. Assigning the same value to an @Observable property still emits
    // a change notification, which would force SwiftUI to re-run the body.
    func open() {
        guard notchState != .open else { return }
        notchState = .open
    }
    func close() {
        guard notchState != .closed else { return }
        notchState           = .closed
        userSelectedModuleID = nil
    }

    func selectModule(id: String) {
        userSelectedModuleID = id
    }
}
