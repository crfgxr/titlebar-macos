# CLAUDE.md — TitleBar macOS

## Architecture
- Single Swift file: `Sources/TitleBarApp.swift`
- SwiftUI MenuBarExtra (Build 5 rewrite)
- Reads frontmost window title via Accessibility API (polls every 0.5s)
- Special handling for browsers (Brave, Chrome) — shows window title instead of app name
- Sandbox disabled (`com.apple.security.app-sandbox` = false) for Accessibility API access

## Build & Distribution
- Distributed via **direct download** (NOT TestFlight/App Store)
- Build & sign: `fastlane mac direct`
- Local install: `./install.sh` (builds Release, copies to /Applications, relaunches)
- `build.sh` is outdated — use `install.sh` or fastlane instead
- Signing: Developer ID Application, automatic style
- No encryption used — export compliance answer is "No"

## Guidelines
- Prefer editing Swift sources; avoid modifying generated build artifacts
- Keep changes aligned with existing Swift style and macOS app conventions
- Touch signing/provisioning files only when explicitly requested
- App icons should include an alpha channel (transparent background)

## Menu Bar
- SF Symbol: `macwindow`

## Icons
- App icon source: `assets/TitleBar.png` (1024x1024, alpha channel)
- Compiled icon: `Resources/TitleBar.icns`
- Generated via Python/Pillow script — dark squircle with blue-purple gradient title bar

## Project Structure
- `Sources/` — Swift source files (entry: `TitleBarApp.swift`)
- `Resources/` — App resources and assets
- `assets/` — Source assets (app icon PNG)
- `TitleBar.xcodeproj` — Xcode project
- `Info.plist`, `TitleBar.entitlements` — App metadata and entitlements
- `install.sh` — Build and install to /Applications
- `fastlane/` — Release automation
