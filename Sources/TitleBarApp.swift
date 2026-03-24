import SwiftUI
import ApplicationServices
import Carbon.HIToolbox

// MARK: - Window Info

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

// MARK: - Key Combo

struct KeyCombo: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let defaultCombo = KeyCombo(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey | shiftKey))

    var displayString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "\u{2303}" }
        if carbonModifiers & UInt32(optionKey) != 0  { s += "\u{2325}" }
        if carbonModifiers & UInt32(shiftKey) != 0   { s += "\u{21E7}" }
        if carbonModifiers & UInt32(cmdKey) != 0     { s += "\u{2318}" }
        s += keyCodeString(keyCode)
        return s
    }

    func save() {
        UserDefaults.standard.set(Int(keyCode), forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(Int(carbonModifiers), forKey: "hotkeyModifiers")
    }

    static func load() -> KeyCombo {
        let ud = UserDefaults.standard
        guard ud.object(forKey: "hotkeyKeyCode") != nil else { return .defaultCombo }
        return KeyCombo(
            keyCode: UInt32(ud.integer(forKey: "hotkeyKeyCode")),
            carbonModifiers: UInt32(ud.integer(forKey: "hotkeyModifiers"))
        )
    }

    static func fromNSEvent(_ event: NSEvent) -> KeyCombo {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return KeyCombo(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
    }
}

private func keyCodeString(_ code: UInt32) -> String {
    let map: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
        0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
        0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
        0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
        0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
        0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0",
        0x1E: "]", 0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I",
        0x23: "P", 0x24: "Return", 0x25: "L", 0x26: "J", 0x27: "'",
        0x28: "K", 0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/",
        0x2D: "N", 0x2E: "M", 0x2F: ".",
        0x30: "Tab", 0x31: "Space", 0x32: "`",
        0x33: "Delete", 0x35: "Esc",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]
    return map[code] ?? "Key\(code)"
}

// MARK: - Global HotKey Manager

final class HotKeyManager {
    static let shared = HotKeyManager()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var registeredCombo: KeyCombo?
    var onHotKey: (() -> Void)?

    private init() {}

    func register(_ combo: KeyCombo) {
        unregister()
        registeredCombo = combo

        let requiredFlags: NSEvent.ModifierFlags = {
            var flags: NSEvent.ModifierFlags = []
            if combo.carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
            if combo.carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
            if combo.carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
            if combo.carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
            return flags
        }()

        let handler: (NSEvent) -> Void = { [weak self] event in
            let pressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let check: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            guard pressed.intersection(check) == requiredFlags,
                  UInt32(event.keyCode) == combo.keyCode else { return }
            self?.onHotKey?()
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let pressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let check: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            if pressed.intersection(check) == requiredFlags,
               UInt32(event.keyCode) == combo.keyCode {
                self?.onHotKey?()
                return nil
            }
            return event
        }
    }

    func unregister() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        registeredCombo = nil
    }
}

// MARK: - Switcher Controller

@MainActor
final class SwitcherController: ObservableObject {
    static let shared = SwitcherController()
    @Published var isVisible = false
    @Published var selectedIndex = 0
    @Published var windows: [WindowInfo] = []
    private var panel: NSPanel?

    func toggle(with currentWindows: [WindowInfo]) {
        if isVisible {
            cycleNext()
        } else {
            show(windows: currentWindows)
        }
    }

    func show(windows: [WindowInfo]) {
        guard !windows.isEmpty else { return }
        self.windows = windows
        self.selectedIndex = 0
        self.isVisible = true

        if panel == nil { createPanel() }

        guard let panel = panel else { return }
        let height = CGFloat(min(windows.count, 10)) * 36 + 24
        panel.setContentSize(NSSize(width: 380, height: height))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func cycleNext() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % windows.count
    }

    func selectCurrent(titleManager: TitleManager) {
        guard selectedIndex < windows.count else { return }
        let window = windows[selectedIndex]
        titleManager.focusWindow(window)
        hide()
    }

    func hide() {
        isVisible = false
        panel?.orderOut(nil)
    }

    private func createPanel() {
        let p = SwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.backgroundColor = .clear
        p.isMovableByWindowBackground = false
        p.hasShadow = true
        p.animationBehavior = .utilityWindow
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.switcherController = self

        let hosting = NSHostingView(rootView: SwitcherView(controller: self))
        p.contentView = hosting
        self.panel = p
    }
}

// MARK: - Switcher Panel (handles key events)

final class SwitcherPanel: NSPanel {
    weak var switcherController: SwitcherController?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        Task { @MainActor in
            if event.keyCode == 53 { // Esc
                switcherController?.hide()
            } else if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
                if let tm = (NSApp.delegate as? AppDelegate)?.titleManager {
                    switcherController?.selectCurrent(titleManager: tm)
                }
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

// MARK: - Switcher View

struct SwitcherView: View {
    @ObservedObject var controller: SwitcherController

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(controller.windows.enumerated()), id: \.element.id) { index, window in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(window.title)
                            .font(.system(size: 13, weight: index == controller.selectedIndex ? .semibold : .regular))
                            .lineLimit(1)
                        Text(window.appName)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if index == controller.selectedIndex {
                        Image(systemName: "return")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(index == controller.selectedIndex ? Color.accentColor.opacity(0.3) : Color.clear)
                        .padding(.horizontal, 4)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    controller.selectedIndex = index
                    if let tm = (NSApp.delegate as? AppDelegate)?.titleManager {
                        controller.selectCurrent(titleManager: tm)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .frame(width: 380)
        .background(VisualEffectBackground())
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Shortcut Recorder View

struct ShortcutRecorderView: View {
    @Binding var combo: KeyCombo
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: { startRecording() }) {
            Text(isRecording ? "Press shortcut..." : combo.displayString)
                .frame(minWidth: 120)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.bordered)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        HotKeyManager.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Require at least one modifier
            guard !flags.isEmpty, !flags.isSubset(of: [.capsLock, .numericPad, .function]) else {
                return event
            }
            let newCombo = KeyCombo.fromNSEvent(event)
            self.combo = newCombo
            newCombo.save()
            HotKeyManager.shared.register(newCombo)
            stopRecording()
            return nil // consume the event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}

// MARK: - Settings Window

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "TitleBar Settings"
        w.contentView = NSHostingView(rootView: settingsView)
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }
}

struct SettingsView: View {
    @State private var combo = KeyCombo.load()

    var body: some View {
        Form {
            LabeledContent("Keyboard Shortcut") {
                ShortcutRecorderView(combo: $combo)
            }
            Text("This shortcut opens the window switcher.\nPress again to cycle, Esc to close, Return to select.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 340)
    }
}

// MARK: - App

@main
struct TitleBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var titleManager = TitleManager()
    @StateObject private var switcher = SwitcherController.shared

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

            Button("Settings...") {
                SettingsWindowController.shared.show()
            }

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

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var titleManager: TitleManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[TitleBar] App launched with SwiftUI MenuBarExtra")
        requestAccessibilityIfNeeded()
        setupHotKey()
    }

    private func setupHotKey() {
        let combo = KeyCombo.load()
        HotKeyManager.shared.register(combo)
        HotKeyManager.shared.onHotKey = {
            Task { @MainActor in
                let switcher = SwitcherController.shared
                // Get title manager from the running app's state
                if let appDelegate = NSApp.delegate as? AppDelegate,
                   let tm = appDelegate.titleManager {
                    switcher.toggle(with: tm.openWindows)
                }
            }
        }
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

// MARK: - Title Manager

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
        // Register ourselves with AppDelegate so hotkey can access windows
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
        let beforeDash = sanitized.components(separatedBy: " - ").first ?? sanitized
        return String(beforeDash.prefix(20))
    }

    deinit {
        timer?.invalidate()
    }
}
