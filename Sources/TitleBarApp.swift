import SwiftUI
import ApplicationServices

@main
struct TitleBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var titleManager = TitleManager()
    
    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Text("Current: \(titleManager.currentTitle)")
                    .font(.headline)
                Divider()
                Button("Open Accessibility Settings") {
                    openAccessibilitySettings()
                }
                Divider()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(8)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "text.alignleft")
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
    
    private var timer: Timer?
    
    init() {
        NSLog("[TitleBar] TitleManager initialized")
        startMonitoring()
    }
    
    private func startMonitoring() {
        NSLog("[TitleBar] Starting monitoring...")
        
        // Observe app activation
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateTitle()
        }
        
        // Poll every 0.5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTitle()
            }
        }
        
        updateTitle()
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
