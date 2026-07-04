import AppKit

/// A small always-on-top pill with a blinking dot, elapsed time, and Stop button,
/// shown while recording.
@MainActor
final class RecordingHUD {
    static let shared = RecordingHUD()

    private var window: NSWindow?
    private var timer: Timer?
    private var seconds = 0
    private var timeLabel: NSTextField?
    private var onStop: (() -> Void)?
    private var onSnapshot: (() -> Void)?

    func show(onStop: @escaping () -> Void, onSnapshot: (() -> Void)? = nil) {
        self.onStop = onStop
        self.onSnapshot = onSnapshot
        seconds = 0

        let width: CGFloat = 360, height: CGFloat = 44
        guard let screen = NSScreen.main else { return }
        let frame = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - 90,
                           width: width, height: height)
        let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .statusBar
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.isMovableByWindowBackground = true

        let bg = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        bg.material = .hudWindow; bg.blendingMode = .behindWindow; bg.state = .active
        bg.wantsLayer = true; bg.layer?.cornerRadius = 22; bg.layer?.masksToBounds = true

        let dot = NSView(frame: NSRect(x: 16, y: height/2 - 5, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 5
        bg.addSubview(dot)
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0; pulse.toValue = 0.2; pulse.duration = 0.7
        pulse.autoreverses = true; pulse.repeatCount = .infinity
        dot.layer?.add(pulse, forKey: "pulse")

        let label = NSTextField(labelWithString: "00:00")
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.frame = NSRect(x: 36, y: height/2 - 11, width: 70, height: 22)
        bg.addSubview(label)
        timeLabel = label

        if onSnapshot != nil {
            let snap = NSButton(image: NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Screenshot")!,
                                target: self, action: #selector(snapshotTapped))
            snap.bezelStyle = .rounded
            snap.imagePosition = .imageOnly
            snap.frame = NSRect(x: width - 262, y: height/2 - 15, width: 40, height: 30)
            snap.toolTip = "Take a screenshot without stopping the recording"
            bg.addSubview(snap)
        }

        let draw = NSButton(title: "✎ Draw", target: self, action: #selector(drawTapped))
        draw.bezelStyle = .rounded
        draw.frame = NSRect(x: width - 172, y: height/2 - 15, width: 82, height: 30)
        draw.toolTip = "Draw on screen while recording"
        bg.addSubview(draw)

        let stop = NSButton(title: "Stop", target: self, action: #selector(stopTapped))
        stop.bezelStyle = .rounded
        stop.frame = NSRect(x: width - 84, y: height/2 - 15, width: 70, height: 30)
        stop.keyEquivalent = "\r"
        bg.addSubview(stop)

        win.contentView = bg
        win.orderFrontRegardless()
        window = win

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        seconds += 1
        timeLabel?.stringValue = String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    @objc private func stopTapped() {
        hide()
        onStop?()
    }

    @objc private func drawTapped() {
        LiveDrawController.shared.toggle()
    }

    @objc private func snapshotTapped() {
        onSnapshot?()
    }

    func hide() {
        timer?.invalidate(); timer = nil
        window?.orderOut(nil); window = nil
        LiveDrawController.shared.stop()
    }
}
