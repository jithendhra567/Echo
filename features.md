# Echo — Features

## App Launcher

- **Global hotkey** — summons a DynamicIsland-style pill from the menu bar. Hotkey is fully configurable.
- **App search** — searches all installed apps instantly; results are ranked by how frequently you open each app, so the things you use most float to the top.
- **Browser tab search** — searches open tabs across Safari, Chrome, and Arc in real time. Closed tabs persist in history so you can find pages you visited earlier even after closing the browser.
- **Instant Search** — press Enter on a non-app query to open a full web view inside the launcher itself without leaving the keyboard. The page starts prefetching as you type so it's ready when you confirm.
- **Smart row ordering** — Echo learns whether you prefer opening links in the browser or in Instant Search and reorders the two options accordingly.
- **Domain detection** — typing a bare domain (e.g. `github.com`) and pressing Enter navigates directly to it without a Google round-trip.
- **Google fallback** — any query that doesn't match an app or tab gets a one-key Google search.
- **Keyboard navigation** — arrow keys move the selection; Tab switches between the Apps and Clipboard panels; Escape dismisses.

## Inline Utility Engine

Calculations, conversions, and lookups appear as the first result while you type — press Enter to copy the answer.

- **Math** — arithmetic expressions (`(48 * 12) / 4`), percentages (`15% of 80`, `20% off 59.99`), tip totals (`18% tip on 45`).
- **Unit conversion** — length (km ↔ miles, cm ↔ inches, …), weight (kg ↔ lb, oz, …), temperature (°C ↔ °F ↔ K), and storage (MB ↔ GB ↔ TB).
- **Date & time** — relative queries like "next friday", "3 weeks from now", date arithmetic.
- **Unix timestamps** — paste a Unix timestamp to see the human-readable date, or type a date to get its timestamp.
- **World time** — "time in tokyo", "what time is it in london" — looks up the current local time in any city.
- **Currency** — live exchange rates via Frankfurter (e.g. `100 usd to eur`). Rates are cached so conversions work offline; a stale-data notice appears when the network is unavailable.

## Clipboard Manager

- **Continuous capture** — monitors the system clipboard every 500 ms. Copies from any app are saved automatically.
- **Rich content** — stores plain text, rich text (RTF), URLs, and images, each with a visual preview.
- **Source context** — records which app and window title each clip came from.
- **Auto-tagging** — clips are automatically tagged as Text, Code, URL, Image, or Rich Text. Code detection looks for language keywords across multiple languages.
- **Pinning** — pin clips to keep them at the top of the list.
- **Search** — filter your history by content, source app, or URL.
- **Drag & drop** — drag any clip out of the panel and drop it into any app as the appropriate type (text, image, or RTF). The panel never steals focus from the app you're dragging into.
- **Global hotkey** — configurable shortcut (default ⌘⇧V) opens the clipboard panel anywhere.
- **Persistent storage** — history is saved to SQLite so it survives restarts.

## Notch Panel

A pill that lives in the menu bar notch, always visible but never in the way. Hover to peek; the pill expands on interaction.

### Tray (File Shelf)
- Drag any file onto the pill to stash it; the tray appears automatically during a system-wide drag.
- Supports files from Finder, screenshot thumbnails, images from Photos and other apps.
- Choose whether dropped files are **copied** or **moved** into the shelf.
- Select multiple files and drag them all out at once — drop target apps receive them as a native multi-file drag.
- Files persist in `Application Support/Echo/TrayShelf` between sessions.

### Now Playing
- Shows the currently playing track from any audio app (Music, Spotify, Podcasts, YouTube, etc.) using the system MediaRemote framework — no app integration required.
- Displays album artwork, track title, and artist in the closed pill; full playback controls appear on expand.

### Clock & Calendar
- Hover the pill to reveal the current time and date.
- Expanding shows a full month calendar grid alongside the time.
- Optional **camera mirror** — click to open a live preview from the front camera, useful as a quick mirror.

## General

- **Menu bar only** — no Dock icon, no window clutter.
- **Launch at login** — toggle from the Dashboard.
- **Always dark** — the launcher and notch panel use `.darkAqua` regardless of system appearance.
- **Settings Dashboard** — configure hotkeys for the launcher and clipboard panel, browse clipboard history, and manage preferences from a single window (right-click the status bar icon).
- **No dependencies** — pure Swift, no third-party packages.
