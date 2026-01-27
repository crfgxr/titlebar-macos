import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[TitleBar] App launched, creating status item...")
        
        // Use fixed length to guarantee visibility
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        
        configureStatusItemAppearance()
        statusItem.menu = makeMenu()
        
        NSLog("[TitleBar] Status item created, button exists: \(statusItem.button != nil)")

        requestAccessibilityIfNeeded()
        startMonitoring()
        
        NSLog("[TitleBar] Monitoring started")
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func requestAccessibilityIfNeeded() {
        if AXIsProcessTrusted() {
            return
        }

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
            openAccessibilitySettings()
        }
    }

    private func configureStatusItemAppearance() {
        guard let button = statusItem.button else {
            NSLog("[TitleBar] ERROR: statusItem.button is nil!")
            return
        }

        // Set a visible title first
        button.title = "TitleBar"
        
        // Try to add SF Symbol icon
        if let image = NSImage(systemSymbolName: "textformat", accessibilityDescription: "TitleBar") {
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            NSLog("[TitleBar] Icon set successfully")
        } else {
            NSLog("[TitleBar] WARNING: Could not load SF Symbol, using text only")
        }
        
        // Force the button to display
        button.isEnabled = true
        button.needsDisplay = true
        
        NSLog("[TitleBar] Button configured with title: \(button.title)")
    }

    private func startMonitoring() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(handleAppActivation(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateStatusTitle()
        }

        updateStatusTitle()
    }

    @objc private func handleAppActivation(_ notification: Notification) {
        updateStatusTitle()
    }

    private func updateStatusTitle() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            setStatusTitle("NoApp")
            return
        }

        let appName = app.localizedName ?? "NoTitle"
        guard shouldUseWindowTitle(for: app) else {
            setStatusTitle(appName)
            return
        }

        guard AXIsProcessTrusted() else {
            setStatusTitle("NoPerm")
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
                setStatusTitle(capitalizeWords(title))
                return
            }
        }

        setStatusTitle(appName)
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
        return text
            .split(separator: " ")
            .map { word in
                guard let first = word.first else {
                    return ""
                }
                let firstUpper = String(first).uppercased()
                let rest = String(word.dropFirst())
                return firstUpper + rest
            }
            .joined(separator: " ")
    }

    private func setStatusTitle(_ title: String) {
        let sanitized = title.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
        let limited = String(sanitized.prefix(10))
        statusItem.button?.title = limited
        NSLog("[TitleBar] Title updated to: \(limited)")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)

NSLog("[TitleBar] Starting app run loop...")
app.run()
