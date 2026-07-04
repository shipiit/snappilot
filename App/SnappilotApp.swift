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
        .windowStyle(.hiddenTitleBar)
        .commands { menuCommands }

        MenuBarExtra("Snappilot", systemImage: "camera.viewfinder") {
            MenuBarView().environmentObject(app)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(app)
        }
    }

    /// Full app menu bar. No `keyboardShortcut` here — the global Carbon hotkeys already
    /// own those keys, so adding them to menus too would fire captures twice.
    @CommandsBuilder private var menuCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Capture Region") { app.captureRegion() }
            Button("Capture Window") { app.captureWindow() }
            Button("Capture Full Screen") { app.captureFullScreen() }
            Button("Grab Text (OCR)") { app.grabText() }
        }
        CommandMenu("Capture") {
            Button("Capture Region") { app.captureRegion() }
            Button("Capture Window") { app.captureWindow() }
            Button("Capture Full Screen") { app.captureFullScreen() }
            Button("Grab Text (OCR)") { app.grabText() }
            Divider()
            Button("Record Region") { app.toggleRecordRegion() }
            Button("Record Screen") { app.toggleRecordScreen() }
            Button("Stop Recording") { app.stopRecording() }.disabled(!app.isRecording)
            Divider()
            Button("Open Library Folder") { app.openLibraryFolder() }
        }
        CommandGroup(replacing: .help) {
            Button("Snappilot Guide") { WelcomeWindowController.present(app: app) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)   // show in the Dock like a normal app
        HotkeyManager.shared.reload()
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
