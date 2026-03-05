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

Everything lives in `RustDeskScreenOff.swift` (~200 lines), structured as two classes + main entry:

- **`ScreenController`** — Screen blackout via `CGSetDisplayTransferByFormula` (gamma to zero), restore via `CGDisplayRestoreColorSyncSettings`, lock via `open -a ScreenSaverEngine`. Multi-monitor mirroring via `CGConfigureDisplayMirrorOfDisplay` (merge on connect, restore on disconnect). Gamma is invisible to ScreenCaptureKit so remote viewers see normal desktop.

- **`AppDelegate`** — Orchestrates everything. Every 1 second polls `pgrep -fi "rustdesk.*--cm"` to detect active connections. On connect: enable mirroring → black screen. On disconnect: restore screen → disable mirroring → lock. Manages NSStatusItem menu bar UI. Installs LaunchAgent plist for login auto-start.

- **Main entry** — Creates `NSApplication`, sets delegate, calls `app.run()` (no storyboard/NIB).

## Key Technical Details

- `LSUIElement=true` in Info.plist hides Dock icon (menu bar only)
- Gamma stays black as long as the process runs; killing the app restores normal display
- Bundle ID: `com.rustdesk.screen-off`
- LaunchAgent plist written to `~/Library/LaunchAgents/com.rustdesk.screen-off.plist`
