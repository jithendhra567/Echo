import AppKit
import Observation

@Observable
@MainActor
final class NotchTrayViewModel {

    // MARK: - State

    enum TrayState: Equatable { case hidden, compact, expanded }
    enum TransferMode { case copy, move }

    var files:             [TrayFile]    = []
    var state:             TrayState     = .hidden
    var transferMode:      TransferMode  = .copy
    var isDropHighlighted: Bool          = false
    var isDraggingGlobally = false
    var isVisible:         Bool          = false   // drives scale+opacity entry animation

    // MARK: - File management

    func addFiles(_ urls: [URL]) {
        let fresh = urls.filter { u in !files.contains(where: { $0.url == u }) }
                        .map { TrayFile(url: $0) }
        guard !fresh.isEmpty else { return }
        files.append(contentsOf: fresh)
        transition(to: .expanded)
    }

    func remove(id: UUID) {
        files.removeAll { $0.id == id }
    }

    func clearAll() {
        files.removeAll()
    }

    // MARK: - Drag lifecycle

    func globalDragBegan() {
        isDraggingGlobally = true
        if state == .hidden { transition(to: .compact) }
    }

    func globalDragEnded() {
        isDraggingGlobally = false
        isDropHighlighted  = false
        if files.isEmpty { transition(to: .hidden) }
    }

    func setDropTargetActive(_ active: Bool) {
        isDropHighlighted = active
        if active, state == .compact { transition(to: .expanded) }
    }

    func expand() {
        guard state == .compact else { return }
        transition(to: .expanded)
    }

    func collapse() {
        guard state == .expanded else { return }
        transition(to: files.isEmpty ? (isDraggingGlobally ? .compact : .hidden) : .compact)
    }

    // MARK: - Private

    private func transition(to new: TrayState) {
        guard state != new else { return }
        if new == .hidden { isVisible = false }
        state = new
    }
}
