# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

macOS menu bar app (Swift + AppKit, single-file). When a RustDesk remote connection is detected, the local screen goes black for privacy; on disconnect, the screen restores and locks.

## Build & Run

```bash
./build_app.sh              # Compile universal binary (arm64 + x86_64), package .app bundle
open RustDeskScreenOff.app  # Run
```

Build requires macOS 14.0+ SDK. Uses `swiftc` directly (no Xcode project/SPM). Frameworks: AppKit, CoreGraphics.

## Architecture

Everything lives in `RustDeskScreenOff.swift` (~300 lines), structured as three classes + main entry:

- **`ScreenController`** — Blacks out all displays via `CGSetDisplayTransferByFormula` (gamma curves set to zero). Restores with `CGDisplayRestoreColorSyncSettings`. Locks screen via `open -a ScreenSaverEngine`. The gamma change is invisible to ScreenCaptureKit, so remote viewers still see the normal desktop. Also handles multi-monitor mirroring via `CGConfigureDisplayMirrorOfDisplay` — merges all displays into one on connect, restores on disconnect.

- **`LogMonitor`** — Runs `tail -n 0 -F` on two RustDesk log files (`~/Library/Logs/RustDesk/RustDesk_rCURRENT.log` and `.../server/RustDesk_rCURRENT.log`). Parses lines for `"Connection opened from"` and `"Connection closed"`, fires callbacks on main thread.

- **`AppDelegate`** — Orchestrates everything. Manages NSStatusItem menu bar UI, wires LogMonitor callbacks to ScreenController, runs a 5-minute safety timer (`pgrep -f "rustdesk.*--cm"`) as fallback if log events are missed. Installs LaunchAgent plist (`com.rustdesk.screen-off`) for login auto-start. Has a 3-second debounce on connection events.

- **Main entry** — Creates `NSApplication`, sets delegate, calls `app.run()` (no storyboard/NIB).

## Key Technical Details

- `LSUIElement=true` in Info.plist hides Dock icon (menu bar only)
- Gamma stays black as long as the process runs; killing the app restores normal display
- Bundle ID: `com.rustdesk.screen-off`
- LaunchAgent plist written to `~/Library/LaunchAgents/com.rustdesk.screen-off.plist`
