import AppKit
import SwiftUI
@preconcurrency import ScreenCaptureKit
import AVFoundation
import SnapCore

/// Coordinates capture → editor → library. Owned by the app; injected into views.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let library = LibraryStore()

    @Published var ocrLanguages: [String] = ["en-US"]
    @Published var recordSystemAudio = true
    @Published var recordMic = false
    @Published var recordCamera = false
    @Published var recordCursor = true
    @Published var recordCountdown = true
    @Published var recordQuality: RecordQuality = .balanced
    @Published var captureDelay = 0        // seconds before a screenshot (0 = none)
    @Published var isRecording = false

    /// Run a capture after an optional countdown delay (for timed screenshots).
    private func withCaptureDelay(_ action: @escaping () -> Void) {
        guard captureDelay > 0, let screen = NSScreen.main ?? NSScreen.screens.first else { action(); return }
        CountdownOverlay.show(on: screen, from: captureDelay) { action() }
    }

    private var selector: RegionSelector?
    private var editors: [ObjectIdentifier: EditorWindowController] = [:]
    private var hiddenWindows: [NSWindow] = []

    // MARK: Get our own windows out of the shot (like Snagit)

    /// Hide ALL of Snappilot's own visible windows (dashboard, editors, video players,
    /// popovers) so none of them land in the capture or get in the way.
    private func hideOwnWindows() {
        for w in NSApp.windows {
            let cn = String(describing: type(of: w))
            if cn.contains("Popover") || cn.contains("MenuBarExtra") { w.orderOut(nil); continue }
            // Titled content windows = dashboard + any open editor / video preview.
            if w.isVisible && w.styleMask.contains(.titled) {
                hiddenWindows.append(w)
                w.orderOut(nil)
            }
        }
    }

    private func restoreOwnWindows() {
        for w in hiddenWindows { w.orderFront(nil) }
        hiddenWindows.removeAll()
    }

    // MARK: Capture entry points (called from menu bar + hotkeys)

    func captureRegion() { withCaptureDelay { self.runRegion { result in self.openEditor(with: result) } } }

    func captureFullScreen() { withCaptureDelay { self.captureFullScreenNow() } }

    private func captureFullScreenNow() {
        hideOwnWindows()
        Task {
            do {
                try? await Task.sleep(for: .milliseconds(150))   // let our window vanish
                let result = try await CaptureController.captureFullScreen(at: NSEvent.mouseLocation)
                openEditor(with: result)
            } catch {
                restoreOwnWindows()
                Toast.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func captureWindow() { withCaptureDelay { self.captureWindowNow() } }

    private func captureWindowNow() {
        hideOwnWindows()
        selector = RegionSelector()
        selector?.present(mode: .window) { [weak self] outcome in
            guard let self else { return }
            guard case let .window(id, _) = outcome else { self.restoreOwnWindows(); return }
            Task {
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    guard let win = content.windows.first(where: { $0.windowID == id }) else {
                        Toast.show("Couldn't capture that window.", symbol: "exclamationmark.triangle.fill"); return
                    }
                    let image = try await CaptureController.captureWindowImage(win)
                    let sel = CaptureSelection(rect: win.frame, displayID: 0, scale: NSScreen.main?.backingScaleFactor ?? 2)
                    self.openEditor(with: CaptureResult(image: image, selection: sel))
                } catch {
                    self.restoreOwnWindows()
                    Toast.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    /// Grab text: select a region, OCR it, copy to clipboard.
    func grabText() { withCaptureDelay { self.grabTextNow() } }

    private func grabTextNow() {
        runRegion { result in
            Task {
                defer { self.restoreOwnWindows() }
                do {
                    let lines = try await OCR.recognize(result.image, languages: self.ocrLanguages)
                    let text = lines.joined(separator: "\n")
                    if text.isEmpty {
                        Toast.show("No text found.", symbol: "text.viewfinder")
                    } else {
                        let pb = NSPasteboard.general
                        pb.clearContents(); pb.setString(text, forType: .string)
                        Toast.show("Copied \(lines.count) line\(lines.count == 1 ? "" : "s") of text", symbol: "doc.on.clipboard.fill")
                    }
                } catch { Toast.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill") }
            }
        }
    }

    func openLibraryFolder() {
        NSWorkspace.shared.open(library.root)
    }

    // MARK: Recording

    /// Record a region the user drags out.
    func recordRegion() {
        hideOwnWindows()
        selector = RegionSelector()
        selector?.present(mode: .region) { [weak self] outcome in
            guard let self else { return }
            guard case let .region(screen, rect) = outcome else { self.restoreOwnWindows(); return }
            self.showReadyToRecord(rect: rect, on: screen)
        }
    }

    /// Record the whole screen under the pointer.
    func recordScreen() {
        hideOwnWindows()
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main
        guard let screen else { restoreOwnWindows(); return }
        showReadyToRecord(rect: nil, on: screen)
    }

    /// Show the "Ready to Record" panel, then countdown, then record.
    private func showReadyToRecord(rect: CGRect?, on screen: NSScreen) {
        RecordReadyController.present(app: self,
            onRecord: { [weak self] in self?.startWithCountdown(rect: rect, on: screen) },
            onCancel: { [weak self] in self?.restoreOwnWindows() })
    }

    private func startWithCountdown(rect: CGRect?, on screen: NSScreen) {
        // The recorded area in global bottom-left coordinates.
        let globalRect: NSRect = rect.map {
            NSRect(x: screen.frame.minX + $0.minX, y: screen.frame.minY + $0.minY, width: $0.width, height: $0.height)
        } ?? screen.frame

        // Show the frame indicator immediately (visible through the countdown + recording).
        if rect != nil { RecordingFrame.shared.show(globalRect: globalRect) }

        if recordCountdown {
            CountdownOverlay.show(on: screen, regionGlobal: globalRect) { [weak self] in
                self?.beginRecording(rect: rect, on: screen)
            }
        } else {
            beginRecording(rect: rect, on: screen)
        }
    }

    private func beginRecording(rect: CGRect?, on screen: NSScreen) {
        let rec = RecordingController.shared
        rec.onFinish = { [weak self] url in
            guard let self else { return }
            self.isRecording = false
            RecordingHUD.shared.hide()
            WebcamOverlay.shared.hide()
            RecordingFrame.shared.hide()
            self.restoreOwnWindows()
            guard let url else { Toast.show("Recording failed", symbol: "exclamationmark.triangle.fill"); return }
            if let saved = self.library.saveVideo(from: url, width: saved_w, height: saved_h) {
                Toast.show("Recording saved", symbol: "video.fill")
                VideoPreviewWindowController.present(url: self.library.fileURL(for: saved), title: saved.title)
            } else {
                Toast.show("Couldn't save recording", symbol: "exclamationmark.triangle.fill")
            }
        }

        Task {
            // Ask for mic / camera access gracefully — if denied, just drop that feature
            // instead of failing the whole recording.
            var mic = recordMic
            if mic {
                mic = await AppState.ensureAccess(.audio)
                if !mic { Toast.show("Microphone off — recording without it", symbol: "mic.slash.fill") }
            }
            var cam = recordCamera
            if cam {
                cam = await AppState.ensureAccess(.video)
                if !cam { Toast.show("Camera off — recording without webcam", symbol: "video.slash.fill") }
            }

            if cam {
                let area: NSRect = rect.map {
                    NSRect(x: screen.frame.minX + $0.minX, y: screen.frame.minY + $0.minY,
                           width: $0.width, height: $0.height)
                } ?? screen.frame
                WebcamOverlay.shared.show(in: area)
            }

            do {
                try await rec.start(rectInScreen: rect, on: screen,
                                    systemAudio: recordSystemAudio, micAudio: mic,
                                    captureCursor: recordCursor, quality: recordQuality)
                isRecording = true
                RecordingHUD.shared.show { [weak self] in self?.stopRecording() }
            } catch {
                WebcamOverlay.shared.hide()
                RecordingFrame.shared.hide()
                restoreOwnWindows()
                Toast.show("Couldn't start recording — check Screen Recording permission in System Settings.",
                           symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// Returns true if access to the media type is (or becomes) authorized.
    static func ensureAccess(_ type: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: type)
        default: return false
        }
    }

    // Pixel dimensions for the current recording, resolved for the library record.
    private var saved_w: Int { Int((RecordingController.shared.recordingPixelSize.width)) }
    private var saved_h: Int { Int((RecordingController.shared.recordingPixelSize.height)) }

    func stopRecording() {
        RecordingController.shared.stop()
    }

    /// Hotkey-friendly toggles: start if idle, stop if already recording.
    func toggleRecordRegion() { isRecording ? stopRecording() : recordRegion() }
    func toggleRecordScreen() { isRecording ? stopRecording() : recordScreen() }

    // MARK: Helpers

    private func runRegion(_ handler: @escaping (CaptureResult) -> Void) {
        hideOwnWindows()
        selector = RegionSelector()
        selector?.present(mode: .region) { [weak self] outcome in
            guard let self else { return }
            guard case let .region(screen, rect) = outcome else { self.restoreOwnWindows(); return }
            Task {
                do {
                    let result = try await CaptureController.captureRegion(rect, on: screen)
                    handler(result)
                } catch {
                    self.restoreOwnWindows()
                    Toast.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    private func openEditor(with result: CaptureResult) {
        restoreOwnWindows()   // bring the dashboard back behind the editor
        // Save the capture to the library immediately so it shows up right away; the
        // editor overwrites this file with annotations when the user hits Done.
        let record = library.saveImage(result.image)
        let controller = EditorWindowController(image: result.image, appState: self, recordID: record?.id)
        editors[ObjectIdentifier(controller)] = controller
        controller.onClose = { [weak self] c in self?.editors[ObjectIdentifier(c)] = nil }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
