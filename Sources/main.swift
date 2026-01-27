import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Loading"
        statusItem.menu = makeMenu()

        requestAccessibilityIfNeeded()
        startMonitoring()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
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
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
