import AppKit
import SwiftUI

/// Hosts the first-run walkthrough in its own centered window.
@MainActor
final class WelcomeWindowController: NSWindowController {
    static var shared: WelcomeWindowController?

    static func present(app: AppState) {
        if let existing = shared {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = WelcomeWindowController(app: app)
        shared = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(app: AppState) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 600),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        let root = WelcomeView(onFinish: { [weak window] in window?.performClose(nil) })
            .environmentObject(app)
        window.contentView = NSHostingView(rootView: root)
    }

    required init?(coder: NSCoder) { fatalError() }
}
