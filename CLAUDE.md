# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Echo is a macOS-only clipboard manager (similar to Paste.app). It runs as a menu-bar-only app (`LSUIElement = true`) with no dock icon.

- **Language:** Swift 6 (`SWIFT_VERSION = 6.0`)
- **SDK:** macOS only (`SDKROOT = macosx`, deployment target 26.4)
- **Concurrency:** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — all types are `@MainActor` by default unless explicitly `nonisolated` or wrapped in an `actor`.

## Build

Open `Echo.xcodeproj` in Xcode and run (⌘R). No Swift Package dependencies.

```bash
# CLI build
xcodebuild -project Echo.xcodeproj -scheme Echo -configuration Debug

# CLI test (add a test target first)
xcodebuild test -project Echo.xcodeproj -scheme Echo -destination 'platform=macOS'
```

## Architecture

```
Echo/
├── EchoApp.swift              # @main; NSApplicationDelegateAdaptor → AppDelegate; Settings scene
├── AppDelegate.swift          # Wires up all subsystems; owns status bar + global hotkey
├── ClipViewModel.swift        # @Observable @MainActor; drives UI; bridges monitor ↔ store ↔ panel
├── ContentView.swift          # Settings window: accessibility permission onboarding UI
│
├── Models/
│   └── Clip.swift             # Clip struct (Sendable); ClipContentType enum; Date.relativeFormatted
│
├── Clipboard/
│   ├── ClipboardMonitor.swift # Polls NSPasteboard every 500 ms; captures clips; calls store.save + onNewClip
│   └── AppMetadataCapture.swift # AX API → focused window title; NSWorkspace → front app
│
├── Database/
│   └── ClipStore.swift        # `actor`; raw SQLite3; save / fetchRecent / delete
│
├── UI/
│   ├── ClipboardPanel.swift   # NSPanel subclass (.nonactivatingPanel); spring slide-up animation
│   ├── ClipDashboardView.swift# Horizontal LazyHStack of ClipCardViews; glassmorphism background
│   └── ClipCardView.swift     # Per-clip card; image/text/RTF preview; drag via .onDrag; hover spring
│
├── Permissions/
│   └── AccessibilityPermission.swift # AXIsProcessTrusted wrapper; background polling until granted
│
└── Info.plist                 # LSUIElement=true; NSAccessibilityUsageDescription
```

### Data flow

```
NSPasteboard ──poll 500ms──▶ ClipboardMonitor ──save──▶ ClipStore (actor/SQLite)
                                    │
                               onNewClip
                                    │
                                    ▼
                            ClipViewModel.loadClips() ──fetchRecent──▶ ClipStore
                                    │
                              @Observable → SwiftUI auto-updates
                                    │
                            ClipboardPanel (NSPanel) ── hosts ──▶ ClipDashboardView
                                                                         │
                                                                   ClipCardView
                                                                   .onTapGesture → viewModel.copy(clip)
                                                                   .onDrag       → clip.itemProvider
```

### Key design decisions

**`NSPanel` with `.nonactivatingPanel`**: The panel never becomes the key window, so the previously active app (e.g. VS Code) stays focused — this is what makes drag-and-drop out of the panel seamless.

**`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`**: Every class/struct/enum is implicitly `@MainActor`. The explicit annotation in the code is redundant but kept for clarity. Only `actor ClipStore` and `nonisolated` functions opt out.

**`ClipStore.db` as `nonisolated(unsafe)`**: SQLite is initialized synchronously in `init()` (which is `nonisolated` in Swift 6). After init, all access flows through the actor's serial executor, so thread safety is upheld by design.

**Suppress re-capture**: `ClipboardMonitor.suppressNextCapture()` is called before programmatic pasteboard writes (in `ClipViewModel.copy`) so the monitor ignores the resulting change event and doesn't create a duplicate history entry.

**Spring animation**: `ClipboardPanel.show()` uses `CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)` — a cubic-bezier approximation of a spring with slight overshoot.

### Permissions

The app requests Accessibility access on first launch. Without it:
- `AppMetadataCapture` silently returns `nil` for `windowTitle` (clips still capture app name + bundle ID)
- `NSEvent.addGlobalMonitorForEvents` is registered but receives no events until the user grants access in **System Settings → Privacy & Security → Accessibility**

The global hotkey (⌘⇧V) and Escape-to-close both rely on this permission.

### Adding new content types

1. Add a case to `ClipContentType` in `Models/Clip.swift`
2. Handle capture in `ClipboardMonitor.capture(from:)`
3. Add drag representation in `Clip.itemProvider`
4. Add preview in `ClipCardView.contentArea`
