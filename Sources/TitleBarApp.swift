import SwiftUI
import ApplicationServices

// MARK: - Private AX API

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

// MARK: - Private CGS APIs for Spaces

private let cgsConnection: UInt32 = {
    typealias CGSMainConnectionIDFunc = @convention(c) () -> UInt32
    guard let handle = dlopen(nil, RTLD_LAZY),
          let sym = dlsym(handle, "CGSMainConnectionID") else { return 0 }
    let fn = unsafeBitCast(sym, to: CGSMainConnectionIDFunc.self)
    return fn()
}()

private func cgsGetActiveSpace() -> UInt64 {
    typealias Func = @convention(c) (UInt32) -> UInt64
    guard let handle = dlopen(nil, RTLD_LAZY),
          let sym = dlsym(handle, "CGSGetActiveSpace") else { return 0 }
    let fn = unsafeBitCast(sym, to: Func.self)
    return fn(cgsConnection)
}

private func cgsCopyManagedDisplaySpaces() -> [[String: Any]]? {
    typealias Func = @convention(c) (UInt32) -> CFArray?
    guard let handle = dlopen(nil, RTLD_LAZY),
          let sym = dlsym(handle, "CGSCopyManagedDisplaySpaces") else { return nil }
    let fn = unsafeBitCast(sym, to: Func.self)
    guard let result = fn(cgsConnection) else { return nil }
    return result as? [[String: Any]]
}

private func cgsCopySpacesForWindows(_ windowIDs: [UInt32]) -> [UInt64: UInt64] {
    typealias Func = @convention(c) (UInt32, UInt32, CFArray) -> CFArray?
    guard let handle = dlopen(nil, RTLD_LAZY),
          let sym = dlsym(handle, "CGSCopySpacesForWindows") else { return [:] }
    let fn = unsafeBitCast(sym, to: Func.self)

    var mapping: [UInt64: UInt64] = [:]
    for wid in windowIDs {
        let arr = [wid as NSNumber] as CFArray
        guard let spaces = fn(cgsConnection, 0x7, arr) as? [NSNumber],
              let spaceID = spaces.first?.uint64Value else { continue }
        mapping[UInt64(wid)] = spaceID
    }
    return mapping
}

// MARK: - Space Manager

@MainActor
final class SpaceManager: ObservableObject {
    static let shared = SpaceManager()
    @Published var currentSpaceNumber: Int = 1
    @Published var spaceNames: [UInt64: String] = [:]
    private var spaceOrder: [UInt64] = []

    func update() {
        let activeSpaceID = cgsGetActiveSpace()
        refreshSpaceList()
        if let index = spaceOrder.firstIndex(of: activeSpaceID) {
            currentSpaceNumber = index + 1
        }
    }

    private func refreshSpaceList() {
        guard let displays = cgsCopyManagedDisplaySpaces() else { return }
        var order: [UInt64] = []
        var names: [UInt64: String] = [:]
        var desktopIndex = 1

        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            for space in spaces {
                guard let id64 = space["id64"] as? UInt64 else { continue }
                let type = space["type"] as? Int ?? 0
                order.append(id64)
                if type == 4 {
                    names[id64] = "Fullscreen"
                } else {
                    names[id64] = "Desktop \(desktopIndex)"
                    desktopIndex += 1
                }
            }
        }
        spaceOrder = order
        spaceNames = names
    }

    func spaceName(for spaceID: UInt64) -> String {
        if spaceID == 0 { return "All Desktops" }
        return spaceNames[spaceID] ?? "Desktop"
    }
}

// MARK: - Window Info

struct WindowInfo: Identifiable {
    var id: String { "\(windowID)-\(title)" }
    let title: String
    let appName: String
    let pid: pid_t
    let spaceID: UInt64
    let windowID: UInt32
}

struct DesktopWindowGroup: Identifiable {
    let id: UInt64
    let spaceName: String
    let appGroups: [AppWindowGroup]
}

struct AppWindowGroup: Identifiable {
    let id: String
    let appName: String
    let windows: [WindowInfo]
}

// MARK: - App

@main
struct TitleBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var titleManager = TitleManager()

    var body: some Scene {
        MenuBarExtra {
            ForEach(titleManager.desktopGroups) { desktop in
                Section {
                    ForEach(desktop.appGroups) { group in
                        Section(group.appName) {
                            ForEach(group.windows) { window in
                                Button {
                                    titleManager.focusWindow(window)
                                } label: {
                                    Text(String(window.title.prefix(30)))
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(desktop.spaceName)
                        if desktop.id == cgsGetActiveSpace() {
                            Text("(current)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if titleManager.openWindows.isEmpty {
                Text("No windows")
            }

            Divider()

            Button("Accessibility Settings...") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("Version \(version)")
                    .foregroundColor(.secondary)
            }

            Button("Quit TitleBar") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "macwindow")
                Text(titleManager.displayTitle)
            }
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var titleManager: TitleManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[TitleBar] App launched with SwiftUI MenuBarExtra")
        requestAccessibilityIfNeeded()
    }

    private func requestAccessibilityIfNeeded() {
        if AXIsProcessTrusted() {
            NSLog("[TitleBar] Already trusted for accessibility")
            return
        }

        NSLog("[TitleBar] Requesting accessibility access...")
        NSApp.activate(ignoringOtherApps: true)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            showAccessibilityOnboardingIfNeeded()
        }
    }

    private func showAccessibilityOnboardingIfNeeded() {
        let key = "AccessibilityOnboardingShown"
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: key) { return }
        defaults.set(true, forKey: key)

        let alert = NSAlert()
        alert.messageText = "Enable Accessibility Access"
        alert.informativeText = "TitleBar needs Accessibility access to read window titles. Click Open Settings, enable TitleBar, then relaunch."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Title Manager

@MainActor
final class TitleManager: ObservableObject {
    @Published var currentTitle: String = "Loading..."
    @Published var displayTitle: String = "TitleBar"
    @Published var openWindows: [WindowInfo] = []
    let spaceManager = SpaceManager.shared

    var desktopGroups: [DesktopWindowGroup] {
        let grouped = Dictionary(grouping: openWindows) { $0.spaceID }
        return grouped.map { (spaceID, windows) in
            let appGrouped = Dictionary(grouping: windows) { $0.appName }
            let appGroups = appGrouped.map { AppWindowGroup(id: $0.key, appName: $0.key, windows: $0.value) }
                .sorted { $0.appName < $1.appName }
            return DesktopWindowGroup(
                id: spaceID,
                spaceName: spaceManager.spaceName(for: spaceID),
                appGroups: appGroups
            )
        }.sorted { $0.spaceName < $1.spaceName }
    }

    private var timer: Timer?
    private var titleCache: [UInt32: String] = [:]  // windowID -> last known title

    init() {
        NSLog("[TitleBar] TitleManager initialized")
        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.titleManager = self
        }
        startMonitoring()
    }

    private func startMonitoring() {
        NSLog("[TitleBar] Starting monitoring...")

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateTitle()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.spaceManager.update()
            self?.updateWindows()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTitle()
                self?.updateWindows()
            }
        }

        updateTitle()
        updateWindows()
    }

    private func updateTitle() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            currentTitle = "No App"
            displayTitle = "NoApp"
            return
        }

        let appName = app.localizedName ?? "Unknown"

        guard shouldUseWindowTitle(for: app) else {
            currentTitle = appName
            displayTitle = truncate(appName)
            return
        }

        guard AXIsProcessTrusted() else {
            currentTitle = "\(appName) (No Permission)"
            displayTitle = "NoPerm"
            return
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindow: CFTypeRef?
        let windowError = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        if windowError == .success, let window = focusedWindow {
            let windowElement = unsafeBitCast(window, to: AXUIElement.self)
            var titleValue: CFTypeRef?
            let titleError = AXUIElementCopyAttributeValue(
                windowElement,
                kAXTitleAttribute as CFString,
                &titleValue
            )

            if titleError == .success, let title = titleValue as? String, !title.isEmpty {
                let capitalized = capitalizeWords(title)
                currentTitle = capitalized
                displayTitle = truncate(capitalized)
                return
            }
        }

        currentTitle = appName
        displayTitle = truncate(appName)
    }

    private func updateWindows() {
        guard AXIsProcessTrusted() else {
            openWindows = []
            return
        }

        spaceManager.update()

        // Step 1: Get ALL windows across all spaces via CGWindowList
        var cgWindows: [(id: UInt32, pid: pid_t, name: String?)] = []
        if let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for info in windowList {
                guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                      let wid = info[kCGWindowNumber as String] as? UInt32,
                      let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
                let name = info[kCGWindowName as String] as? String
                cgWindows.append((id: wid, pid: pid, name: name))
            }
        }

        // Step 2: Map all window IDs to spaces
        let allWindowIDs = cgWindows.map { $0.id }
        let spaceMapping = cgsCopySpacesForWindows(allWindowIDs)

        // Step 3: Get window titles via AX for current space (AX has reliable titles)
        var axTitles: [pid_t: [(title: String, windowID: UInt32)]] = [:]
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let appNames: [pid_t: String] = Dictionary(
            apps.map { ($0.processIdentifier, $0.localizedName ?? "Unknown") },
            uniquingKeysWith: { first, _ in first }
        )

        for app in apps {
            if app.localizedName == "TitleBar" { continue }
            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)

            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let axWindows = windowsRef as? [AXUIElement] else { continue }

            for axWindow in axWindows {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let title = titleRef as? String, !title.isEmpty {
                    var windowID: CGWindowID = 0
                    _AXUIElementGetWindow(axWindow, &windowID)
                    axTitles[pid, default: []].append((title: title, windowID: windowID))
                }
            }
        }

        // Step 4: Build window list — prefer AX titles, fall back to cache, then CG names
        var windows: [WindowInfo] = []
        var seenWindowIDs: Set<UInt32> = []

        // First: add all AX windows (current space, reliable titles) and update cache
        for (pid, titles) in axTitles {
            let appName = appNames[pid] ?? "Unknown"
            for t in titles {
                titleCache[t.windowID] = t.title  // cache for when we leave this space
                let spaceID = spaceMapping[UInt64(t.windowID)] ?? 0
                windows.append(WindowInfo(title: t.title, appName: appName, pid: pid, spaceID: spaceID, windowID: t.windowID))
                seenWindowIDs.insert(t.windowID)
            }
        }

        // Then: add CG windows from OTHER spaces (not already seen via AX)
        // Use cached title, CG name, or app name (deduplicated per app+space)
        var seenAppSpace: Set<String> = []  // track "pid-spaceID" for app name fallback dedup
        for cg in cgWindows {
            guard !seenWindowIDs.contains(cg.id),
                  let appName = appNames[cg.pid],
                  appName != "TitleBar" else { continue }
            let spaceID = spaceMapping[UInt64(cg.id)] ?? 0
            if spaceID == 0 { continue }
            // Try: cached AX title → CG window name → app name (deduped)
            if let cached = titleCache[cg.id] {
                windows.append(WindowInfo(title: cached, appName: appName, pid: cg.pid, spaceID: spaceID, windowID: cg.id))
                seenWindowIDs.insert(cg.id)
            } else if let cgName = cg.name, !cgName.isEmpty {
                windows.append(WindowInfo(title: cgName, appName: appName, pid: cg.pid, spaceID: spaceID, windowID: cg.id))
                seenWindowIDs.insert(cg.id)
            } else {
                // No title available — show one entry per app per space as fallback
                let key = "\(cg.pid)-\(spaceID)"
                if seenAppSpace.insert(key).inserted {
                    windows.append(WindowInfo(title: appName, appName: appName, pid: cg.pid, spaceID: spaceID, windowID: cg.id))
                    seenWindowIDs.insert(cg.id)
                }
            }
        }

        // Clean cache: remove entries for windows that no longer exist
        let activeWindowIDs = Set(cgWindows.map { $0.id })
        titleCache = titleCache.filter { activeWindowIDs.contains($0.key) }

        openWindows = windows
    }

    func focusWindow(_ window: WindowInfo) {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return }
        app.activate(options: [.activateIgnoringOtherApps])

        let appElement = AXUIElementCreateApplication(window.pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return }

        for axWindow in axWindows {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
               let t = titleRef as? String, t == window.title {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                return
            }
        }
    }

    private func shouldUseWindowTitle(for app: NSRunningApplication) -> Bool {
        let browserBundleIds = ["com.brave.Browser", "com.google.Chrome"]
        if let bundleId = app.bundleIdentifier, browserBundleIds.contains(bundleId) {
            return true
        }

        let name = app.localizedName?.lowercased() ?? ""
        return name == "brave browser" || name == "brave" || name == "google chrome"
    }

    private func capitalizeWords(_ text: String) -> String {
        text.split(separator: " ")
            .map { word in
                guard let first = word.first else { return "" }
                return String(first).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private func truncate(_ text: String) -> String {
        let sanitized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let beforeDash = sanitized.components(separatedBy: " - ").first ?? sanitized
        return String(beforeDash.prefix(20))
    }

    deinit {
        timer?.invalidate()
    }
}
