# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Echo is a macOS-only menu-bar app (no dock icon) combining a clipboard manager, an app launcher, and a notch panel.

`NSApp.setActivationPolicy(.accessory)` is set programmatically in `AppDelegate` — **not** via `LSUIElement = true` in Info.plist. `LSUIElement` stamps `kLSServerConnectionStatusProcessIsDaemonMask` on the process, which the WebContent XPC service (backing `WKWebView` in InstantSearch) inherits, crashing on launch.

- **Language:** Swift 6 (`SWIFT_VERSION = 6.0`)
- **SDK:** macOS only (`SDKROOT = macosx`, deployment target 26.4)
- **Concurrency:** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — all types are `@MainActor` by default unless explicitly `nonisolated` or wrapped in an `actor`.

## Build

Open `Echo.xcodeproj` in Xcode and run (⌘R). No Swift Package dependencies.

```bash
# CLI build
xcodebuild -project Echo.xcodeproj -scheme Echo -configuration Debug
```

## Architecture

```
Echo/
├── EchoApp.swift              # @main; NSApplicationDelegateAdaptor → AppDelegate; Settings scene
├── AppDelegate.swift          # Wires all subsystems; status bar; two HotkeyManagers; app-launch tracking
│                              #   left-click → launcher, right-click → menu (Dashboard / Quit)
├── ClipViewModel.swift        # @Observable; bridges ClipboardMonitor ↔ ClipStore ↔ UI
├── ContentView.swift          # Accessibility permission onboarding UI
├── LaunchAtLoginController.swift  # @Observable; SMAppService.mainApp (macOS 13+); toggle login-item
│
├── Models/Clip.swift          # Clip struct (Sendable); ClipContentType enum
├── Clipboard/                 # ClipboardMonitor (500ms poll) + AppMetadataCapture (AX API)
├── Database/ClipStore.swift   # `actor`; raw SQLite3; save / fetchRecent / delete
│
├── UI/                        # ClipboardPanel (NSPanel), ClipDashboardView, ClipCardView
│
├── Launcher/                  # App launcher (DynamicIsland-style)
│   ├── DynamicIslandWindow.swift  # Transparent NSPanel; morphs in SwiftUI; keyboard nav
│   ├── LauncherViewModel.swift    # Orchestrates apps + tabs + utility + instant-search results
│   ├── AppSearchEngine.swift      # Indexes installed apps; usage-frequency ranking
│   ├── HotkeyManager.swift        # Carbon hotkey registration
│   ├── LauncherSettings.swift     # UserDefaults-backed hotkey persistence; onChange callbacks
│   ├── AppInfo.swift              # App metadata struct
│   ├── DynamicIslandView.swift    # SwiftUI search UI inside the island shape
│   ├── InstantSearch/             # In-launcher WKWebView panel
│   │   ├── InstantSearchSession.swift     # WKWebView wrapper; prefetch (280ms delay) + load
│   │   ├── InstantSearchURLResolver.swift # Domain vs Google search URL resolution
│   │   ├── InstantSearchUsageStore.swift  # actor; tracks instant vs Google opens to reorder rows
│   │   ├── InstantSearchRow.swift         # SwiftUI row shown when no app results match
│   │   └── InstantSearchWebView.swift     # NSViewRepresentable hosting the WKWebView
│   └── Utility/                   # Inline calculation / conversion results (shown above app rows)
│       ├── UtilityResult.swift            # Result model: kind, copyText, previewText, detailText
│       ├── UtilityQueryNormalizer.swift   # Trims, lowercases, collapses whitespace, fixes typos
│       ├── UtilityParser.swift            # Dispatches to calculation / unit / datetime engines
│       ├── UtilityFormatting.swift        # Number & unit display formatting helpers
│       ├── UnitLexicon.swift              # Maps natural-language unit tokens to canonical types
│       ├── WorldTimezoneLexicon.swift     # Maps city/country names to TimeZone identifiers
│       ├── Currency/                      # Live currency conversion via Frankfurter API
│       │   ├── CurrencyQueryParser.swift  # Detects "100 usd to eur" patterns
│       │   ├── CurrencyConversionService.swift  # Singleton; fetches + caches rates
│       │   ├── FrankfurterAPIClient.swift # HTTP client for api.frankfurter.app
│       │   └── …                          # CurrencyLexicon, CurrencyQuery, cache models/store
│       └── Engines/               # Pure computation; no I/O
│           ├── CalculationEngine.swift
│           ├── UnitConversionEngine.swift
│           ├── DateTimeEngine.swift
│           ├── TimestampEngine.swift
│           └── WorldTimeEngine.swift
│
├── Browser/                   # Browser tab access via AppleScript (Safari, Chrome, Arc)
│   ├── BrowserTabEngine.swift # fetchTabs / focusTab via NSAppleScript on dedicated queue
│   ├── BrowserTabStore.swift  # actor; SQLite persistence of tab history
│   └── BrowserTab.swift       # Tab model struct
│
├── Notch/                     # Menu-bar notch pill (always visible, level .mainMenu+3)
│   ├── NotchPanel.swift       # NSPanel; ignoresMouseEvents toggle; drag detection
│   ├── NotchViewModel.swift   # State (closed/open); module priority (Tray > Music > Clock)
│   ├── NotchView.swift        # SwiftUI pill UI
│   ├── NotchShape.swift       # Notch-shaped Shape; animatableData interpolates corners (liquid expand)
│   ├── NotchLayoutGuide.swift # @Observable topInset; posts .echoNotchTopInsetDidChange
│   ├── NotchSizing.swift      # Notch geometry; screen detection; fullscreen suppression
│   ├── GlobalDragMonitor.swift# System-wide drag tracking for tray drop zone
│   ├── NotchMirrorCapture.swift  # AVCaptureSession for camera mirror (requires Camera permission)
│   ├── TrayFile.swift         # File metadata struct for the Tray drop-zone (preview + icon)
│   ├── Modules/               # NotchModule protocol; TrayModule; MusicModule; ClockModule
│   └── MediaRemote/           # Now-playing info via MediaRemote private framework
│
├── Utilities/EchoIconImage.swift  # Shared sonar-ring drawing logic for menu bar + app icon renderer
├── Settings/AppSettings.swift     # @Observable UserDefaults-backed app settings (retention days,
│                                  #   ignored websites/apps, pause capture, image capture, concealed-skip);
│                                  #   nonisolated static readers for actor access
├── Dashboard/
│   ├── DashboardView.swift        # NavigationSplitView: General / Clipboard / Privacy / Statistics / History / About
│   └── StatsProvider.swift        # Aggregates stats: top websites (tab history + URL clips),
│                                  #   most-launched apps (launcher usage), clipboard aggregations
├── Permissions/AccessibilityPermission.swift
└── Info.plist
```

### Data flow

```
NSPasteboard ──poll 500ms──▶ ClipboardMonitor ──save──▶ ClipStore (actor/SQLite)
                                    │
                               onNewClip
                                    ▼
                            ClipViewModel.loadClips() ──fetchRecent──▶ ClipStore
                                    │
                              @Observable → SwiftUI
                                    │
                     ┌──────────────┴──────────────┐
                     ▼                             ▼
             ClipboardPanel                 DynamicIslandWindow
             (ClipDashboardView)            (DynamicIslandView)
                                                   │
                                            LauncherViewModel
                                            ├── AppSearchEngine
                                            ├── BrowserTabEngine ──▶ BrowserTabStore
                                            ├── UtilityParser / CurrencyConversionService (inline results)
                                            └── InstantSearchSession (WKWebView, prefetched)

NSWorkspace.didActivateApplication ──▶ LauncherViewModel.recordSystemActivation()
                                        (keeps frequency rankings current)
```

### Key design decisions

**Two `HotkeyManager` instances**: `AppDelegate` owns `hotkeyManager` (id 1, launcher) and `clipHotkeyManager` (id 2, clipboard panel). Both use Carbon hotkey registration. Escape is handled separately via `NSEvent.addGlobalMonitorForEvents`. Hotkeys are user-configurable and stored in `LauncherSettings` (UserDefaults).

**`DynamicIslandWindow` as transparent passthrough**: baseline `ignoresMouseEvents = true`; hover-guard via `acceptsMouseMovedEvents` lifts on first mouse move so accidental-hover on show is suppressed. The island shape is drawn entirely in SwiftUI — the window frame never changes. Always uses `.darkAqua` appearance regardless of system theme.

**`NotchPanel` click-through**: `ignoresMouseEvents = true` by default (OS-level guarantee — window server skips it). Toggled to `false` only when cursor enters the pill rect. A secondary `PillHostingView.hitTest` guard ensures transparent margins inside the open pill also pass through. Level is `.mainMenu + 3` so it sits above the menu bar.

**`NotchLayoutGuide` coordination**: when the notch pill expands, `NotchPanel.applyScreenLayout()` calls `layoutGuide.setTopInset(...)` which posts `.echoNotchTopInsetDidChange`. `DynamicIslandWindow` observes this notification and calls `reposition()` to shift down, so the launcher never overlaps the open pill.

**`BrowserTabEngine` on dedicated queue**: `NSAppleScript` must not run on `MainActor`. All AppleScript execution uses `DispatchQueue(label: "echo.applescript", qos: .userInitiated)` with `withCheckedThrowingContinuation`. Tab data is cached in-memory; `BrowserTabStore` persists history so closed tabs remain searchable.

**`NSPanel` with `.nonactivatingPanel`**: `ClipboardPanel` never becomes the key window, keeping the previously active app (e.g. VS Code) focused — what makes drag-and-drop out of the panel seamless.

**Suppress re-capture**: `ClipboardMonitor.suppressNextCapture()` is called before programmatic pasteboard writes (`ClipViewModel.copy`) to avoid duplicate history entries.

**Utility row ordering**: `LauncherViewModel` shows results in this vertical order: (1) utility result, (2) app/tab/web rows. `selectedIndex` is offset by `utilityRowCount` when resolving which item is selected.

**`InstantSearchSession` prefetch**: when `showsInstantSearchRow` becomes true, `LauncherViewModel.search()` calls `prefetch(url:)`, which waits 280ms before loading — cancels if the user keeps typing. On explicit open, `load(_:force:)` runs immediately. The `WKWebView` uses the default (persistent) `WKWebsiteDataStore` so sessions are preserved. `NSApp.setActivationPolicy(.accessory)` (not `LSUIElement`) is required for the WebContent XPC process to launch cleanly.

**`InstantSearchUsageStore` row ordering**: tracks per-session how often the user opens Instant Search vs. Google in the browser. `prefersGoogleOverInstant` flips when `googleOpens > instantOpens + 2`, causing the Google row to appear above the Instant Search row in the launcher.

**`ClipStore.db` as `nonisolated(unsafe)`**: SQLite is initialized synchronously in `init()` (which is `nonisolated` in Swift 6). All subsequent access flows through the actor's serial executor.

**Notch module priority**: `NotchViewModel.activeModule` follows: (1) drag in flight → Tray forced; (2) first module where `isActive == true`; (3) Clock fallback (peek-on-hover, reports `isActive == false`).

### Permissions

The app requests Accessibility access on first launch. Without it:
- `AppMetadataCapture` returns `nil` for `windowTitle`
- `NSEvent.addGlobalMonitorForEvents` receives no events

The global hotkeys and Escape-to-close both rely on this permission.

**Camera** is requested lazily when `NotchMirrorCapture.startIfNeeded()` is called (from `ClockModule`). The capture session runs on a dedicated `DispatchQueue` (`com.echo.notch.mirror.session`); the `AVCaptureVideoPreviewLayer` is hosted in `NotchMirrorCameraPreview` (`NSViewRepresentable`).

### Adding new content types

1. Add a case to `ClipContentType` in `Models/Clip.swift`
2. Handle capture in `ClipboardMonitor.capture(from:)`
3. Add drag representation in `Clip.itemProvider`
4. Add preview in `ClipCardView.contentArea`

### Adding a new notch module

1. Conform to `NotchModule` protocol in `Notch/Modules/`
2. Add an instance to `NotchViewModel` and include it in `modules`
3. Module priority is determined by position in the `modules` array
