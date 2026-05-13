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

    let tray:  TrayModule
    let clock: ClockModule

    /// Display order is *also* priority order — `first(where: $0.isActive)`
    /// picks Tray if files / drag, else Clock.
    var modules: [any NotchModule] { [tray, clock] }

    // MARK: - State

    /// Whether the pill is visually expanded.
    var notchState: NotchState = .closed
    /// Tracked separately so we can fade non-interactive overlays.
    var isHovering: Bool = false

    /// Notch metrics for the current screen.
    var closedNotchSize: CGSize = .init(width: 185, height: 32)

    // MARK: - Init

    init() {
        self.tray  = TrayModule()
        self.clock = ClockModule()
    }

    // MARK: - Active module priority

    /// Priority:
    /// 1. Drag in progress → Tray (forced).
    /// 2. First module whose `isActive == true` (tray with files / drop).
    /// 3. Clock — fallback. Reports `isActive == false`, so when nothing
    ///    else is active the pill stays as the bare notch (closed bar fades
    ///    out), and the clock surface only appears once the user hovers.
    var activeModule: any NotchModule {
        if tray.isDragInFlight {
            return tray
        }
        if let m = modules.first(where: { $0.isActive }) {
            return m
        }
        return clock
    }

    /// True when any module wants to surface itself in the closed pill
    /// (Tray with files / drag). The Clock module reports
    /// false here — it's a peek-on-hover module, not a permanent fixture.
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
        notchState = .closed
    }
}
