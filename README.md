# TitleBar macOS App

A macOS menu bar app that shows the frontmost window's title. Built with SwiftUI MenuBarExtra.

## Features
- Displays the current window title in the menu bar
- Lists all open windows grouped by app
- Click any window to focus it
- Special handling for browsers (shows page title, not app name)

## Requirements
- macOS with Xcode installed
- Accessibility permission (prompted on first launch)

## Install
Build and install to `/Applications`:

```bash
./install.sh
```

## Fastlane
Build, sign, and package for distribution:

```bash
fastlane mac direct
```

## Project Structure
- `Sources/` — Swift source files (entry: `TitleBarApp.swift`)
- `Resources/` — App resources and assets
- `assets/` — Source assets (app icon PNG)
- `generate_icon.py` — Icon generation script (Python/Pillow)
- `TitleBar.xcodeproj` — Xcode project
- `Info.plist`, `TitleBar.entitlements` — App metadata and entitlements
- `install.sh` — Build and install to /Applications
- `fastlane/` — Release automation
