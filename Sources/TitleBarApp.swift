import SwiftUI
import ApplicationServices

struct WindowInfo: Identifiable {
    var id: String { "\(pid)-\(title)" }
    let title: String
    let appName: String
    let pid: pid_t
}

struct AppWindowGroup: Identifiable {
    let id: String
    let appName: String
    let windows: [WindowInfo]
}

@main
struct TitleBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var titleManager = TitleManager()

    var body: some Scene {
        MenuBarExtra {
            ForEach(titleManager.appGroups) { group in
                Section(group.appName) {
                    ForEach(group.windows) { window in
                        Button(window.title) {
                            titleManager.focusWindow(window)
                        }
                    }
                }
            }

            if titleManager.openWindows.isEmpty {
                Text("No windows")
            }

            Divider()

            Button("Accessibility Settings...") {
                openAccessibilitySettings()
            }

            Divider()

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

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
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
        if defaults.bool(forKey: key) {
            return
        }

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

@MainActor
final class TitleManager: ObservableObject {
    @Published var currentTitle: String = "Loading..."
    @Published var displayTitle: String = "TitleBar"
    @Published var openWindows: [WindowInfo] = []

    var appGroups: [AppWindowGroup] {
        let grouped = Dictionary(grouping: openWindows) { $0.appName }
        return grouped.map { AppWindowGroup(id: $0.key, appName: $0.key, windows: $0.value) }
            .sorted { $0.appName < $1.appName }
    }

    private var timer: Timer?

    init() {
        NSLog("[TitleBar] TitleManager initialized")
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

        var windows: [WindowInfo] = []
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }

        for app in apps {
            let appName = app.localizedName ?? "Unknown"
            if appName == "TitleBar" { continue }
            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)

            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let axWindows = windowsRef as? [AXUIElement] else { continue }

            for axWindow in axWindows {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let title = titleRef as? String, !title.isEmpty {
                    windows.append(WindowInfo(title: title, appName: appName, pid: pid))
                }
            }
        }

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
        return String(sanitized.prefix(10))
    }

    deinit {
        timer?.invalidate()
    }
}
