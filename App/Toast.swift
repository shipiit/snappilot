import AppKit

/// A small auto-dismissing HUD near the top of the active screen (capture feedback).
@MainActor
enum Toast {
    static func show(_ message: String, symbol: String = "checkmark.circle.fill") {
        let padding: CGFloat = 16
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let textSize = (message as NSString).size(withAttributes: [.font: font])
        let width = textSize.width + padding * 2 + 28
        let height: CGFloat = 40

        guard let screen = NSScreen.main else { return }
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - 120
        let win = NSWindow(contentRect: NSRect(x: x, y: y, width: width, height: height),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .statusBar
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true

        let icon = NSImageView(frame: NSRect(x: padding, y: (height - 18) / 2, width: 18, height: 18))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .systemGreen
        container.addSubview(icon)

        let label = NSTextField(labelWithString: message)
        label.font = font
        label.textColor = .labelColor
        label.frame = NSRect(x: padding + 24, y: (height - textSize.height) / 2,
                             width: textSize.width + 8, height: textSize.height)
        container.addSubview(label)

        win.contentView = container
        win.alphaValue = 0
        win.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18; win.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3; win.animator().alphaValue = 0
            } completionHandler: { win.orderOut(nil) }
        }
    }
}
