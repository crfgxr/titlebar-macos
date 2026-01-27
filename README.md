# TitleBar macOS App

TitleBar is a macOS app written in Swift.

## Requirements
- macOS with Xcode installed

## Getting Started
1. Open `TitleBar.xcodeproj` in Xcode.
2. Select the app target and run.

## Build Script
Run the local build script from the project root:

```bash
./build.sh
```

## Fastlane
Fastlane automation lives in `fastlane/`.

```bash
fastlane mac create_app
fastlane mac release
```

## Project Structure
- `Sources/` Swift source files (entry: `Sources/main.swift`)
- `Resources/` app resources and assets
- `TitleBar.xcodeproj` Xcode project
- `Info.plist`, `TitleBar.entitlements` app metadata and entitlements
- `project.yml` project configuration
- `fastlane/` release automation
- `build.sh` build script
