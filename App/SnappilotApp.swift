import SwiftUI

@main
struct SnappilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState.shared

    var body: some Scene {
        Window("Snappilot", id: "main") {
            HomeView().environmentObject(app)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { menuCommands }

        MenuBarExtra("Snappilot", systemImage: "camera.viewfinder") {
            MenuBarView().environmentObject(app)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(app)
        }
    }

    /// Full app menu bar. Each item shows its shortcut in the title (the global Carbon
    /// hotkeys already own those keys, so we don't attach a real `keyboardShortcut` too —
    /// that would fire captures twice — but the user can still see every shortcut here).
    @CommandsBuilder private var menuCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(item("Capture Region", .captureRegion)) { app.captureRegion() }
            Button(item("Capture Window", .captureWindow)) { app.captureWindow() }
            Button(item("Capture Full Screen", .captureFull)) { app.captureFullScreen() }
            Button(item("Grab Text (OCR)", .grabText)) { app.grabText() }
        }
        CommandMenu("Capture") {
            Button(item("Capture Region", .captureRegion)) { app.captureRegion() }
            Button(item("Capture Window", .captureWindow)) { app.captureWindow() }
            Button(item("Capture Full Screen", .captureFull)) { app.captureFullScreen() }
            Button(item("Grab Text (OCR)", .grabText)) { app.grabText() }
            Button(item("Scrolling Capture", .scrollingCapture)) { app.scrollingCapture() }
            Divider()
            Button(item("Record Region", .recordRegion)) { app.toggleRecordRegion() }
            Button(item("Record Screen", .recordScreen)) { app.toggleRecordScreen() }
            Button(item("Record Meeting", .recordMeeting)) { app.recordMeeting() }
            Button(item("Stop Recording", .stopRecording)) { app.stopRecording() }.disabled(!app.isRecording)
            Divider()
            Button("Customize Shortcuts…") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
            Button("Open Library Folder") { app.openLibraryFolder() }
        }
        CommandGroup(replacing: .help) {
            Button("Snappilot Guide") { WelcomeWindowController.present(app: app) }
        }
    }

    /// "Title    ⌃⇧1" — action label with its current shortcut appended.
    private func item(_ title: String, _ action: HotkeyAction) -> String {
        "\(title)    \(HotkeyStore.shared.display(action))"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)   // show in the Dock like a normal app
        AppState.shared.applyAppearance()
        HotkeyManager.shared.reload()
        TaskNotifier.requestAuthorization()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.maximizeMainWindow() }
        if !UserDefaults.standard.bool(forKey: "hasSeenWelcome") {
            WelcomeWindowController.present(app: AppState.shared)
        }
    }

    /// Grow the main window to fill the screen (nice full-page start).
    private func maximizeMainWindow() {
        guard let window = mainWindow() else { return }
        let screen = window.screen ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            window.setFrame(vf, display: true, animate: false)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.title == "Snappilot" || ($0.identifier?.rawValue.contains("main") ?? false) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { maximizeMainWindow() }
        return true
    }
}
