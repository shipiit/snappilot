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
    @Published var recordNoiseCancellation = true
    @Published var recordCamera = false
    @Published var recordCursor = true
    @Published var recordCursorHighlight = false
    @Published var recordCountdown = true
    @Published var recordQuality: RecordQuality = .balanced
    @Published var captureDelay = 0        // seconds before a screenshot (0 = none)
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var generatingNotes = false

    // Meeting Mode: when set, notes are generated from the recording once it stops.
    private var meetingMode = false
    private var lastHadParticipants = false
    private var lastHadYou = false

    func togglePause() {
        if isPaused { RecordingController.shared.resume(); isPaused = false }
        else { RecordingController.shared.pause(); isPaused = true }
    }

    /// Run a capture after an optional countdown delay (for timed screenshots).
    private func withCaptureDelay(_ action: @escaping () -> Void) {
        guard captureDelay > 0, let screen = NSScreen.main ?? NSScreen.screens.first else { action(); return }
        CountdownOverlay.show(on: screen, from: captureDelay) { action() }
    }

    private var selector: RegionSelector?
    private var editor: EditorWindowController?      // one reusable editor window
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

    /// Record a Google Meet / Zoom meeting: force system audio + mic (with noise
    /// cancellation) so both sides are captured, then auto-generate notes when it stops.
    func recordMeeting() {
        recordSystemAudio = true
        recordMic = true
        recordNoiseCancellation = true
        meetingMode = true
        // For real per-speaker names we read Google Meet's live captions, which needs
        // Accessibility permission — prompt now so it's ready. If not granted, the meeting
        // still works and falls back to You / Participants from the audio.
        if !ScrollCaptureController.accessibilityTrusted() {
            Toast.show("Tip: allow Accessibility so Snappilot can read Meet captions for names",
                       symbol: "captions.bubble")
            ScrollCaptureController.promptAccessibility()
        }
        recordScreen()
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

        Task {
            // Bring the webcam bubble up NOW (before the countdown) so you can see & position
            // it — and so permission is sorted before recording starts.
            if recordCamera {
                switch await AppState.access(.video) {
                case .granted:
                    WebcamOverlay.shared.show(in: globalRect)
                case .denied:
                    recordCamera = false
                    Toast.show("Camera access is off — opening Settings so you can allow it",
                               symbol: "video.slash.fill")
                    AppState.openPrivacyPane("Camera")
                case .noDevice:
                    recordCamera = false
                    Toast.show("No camera found", symbol: "video.slash.fill")
                }
            }
            if recordCountdown {
                CountdownOverlay.show(on: screen, regionGlobal: globalRect) { [weak self] in
                    self?.beginRecording(rect: rect, on: screen)
                }
            } else {
                beginRecording(rect: rect, on: screen)
            }
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
            CursorHighlight.shared.stop()
            self.restoreOwnWindows()
            guard let url else { Toast.show("Recording failed", symbol: "exclamationmark.triangle.fill"); return }
            let wasMeeting = self.meetingMode
            self.meetingMode = false
            let captionLines = wasMeeting ? MeetCaptionReader.shared.stop() : []
            if let saved = self.library.saveVideo(from: url, width: saved_w, height: saved_h) {
                Toast.show("Recording saved", symbol: "video.fill")
                let fileURL = self.library.fileURL(for: saved)
                if wasMeeting {
                    self.generateMeetingNotes(url: fileURL, title: saved.title,
                                              date: saved.createdAt,
                                              hasParticipants: self.lastHadParticipants,
                                              hasYou: self.lastHadYou,
                                              preLines: captionLines)
                } else {
                    VideoPreviewWindowController.present(url: fileURL, title: saved.title)
                }
            } else {
                Toast.show("Couldn't save recording", symbol: "exclamationmark.triangle.fill")
            }
        }

        Task {
            // Ask for mic / camera access gracefully — if denied, just drop that feature
            // instead of failing the whole recording.
            var mic = recordMic
            if mic, await AppState.access(.audio) != .granted {
                mic = false
                Toast.show("Microphone off — opening Settings to allow it", symbol: "mic.slash.fill")
                AppState.openPrivacyPane("Microphone")
            }
            // Camera/webcam is already requested & shown in startWithCountdown.
            do {
                try await rec.start(rectInScreen: rect, on: screen,
                                    systemAudio: recordSystemAudio, micAudio: mic,
                                    captureCursor: recordCursor,
                                    noiseCancellation: recordNoiseCancellation,
                                    quality: recordQuality)
                isRecording = true
                lastHadParticipants = recordSystemAudio
                lastHadYou = mic
                if meetingMode, MeetCaptionReader.supported() { MeetCaptionReader.shared.start() }
                if recordCursorHighlight { CursorHighlight.shared.start() }
                isPaused = false
                RecordingHUD.shared.show(
                    onStop: { [weak self] in self?.stopRecording() },
                    onSnapshot: { [weak self] in self?.snapshotDuringRecording(rect: rect, on: screen) },
                    onPause: { [weak self] in self?.togglePause() })
            } catch {
                WebcamOverlay.shared.hide()
                RecordingFrame.shared.hide()
                restoreOwnWindows()
                Toast.show("Couldn't start recording — check Screen Recording permission in System Settings.",
                           symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    enum AccessResult { case granted, denied, noDevice }

    /// Check/request camera or mic access; prompts if undetermined.
    static func access(_ type: AVMediaType) async -> AccessResult {
        if type == .video, AVCaptureDevice.default(for: .video) == nil { return .noDevice }
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: return .granted
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: type) ? .granted : .denied
        default: return .denied
        }
    }

    /// Open the given Privacy & Security pane (e.g. "Camera", "Microphone").
    static func openPrivacyPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    // Pixel dimensions for the current recording, resolved for the library record.
    private var saved_w: Int { Int((RecordingController.shared.recordingPixelSize.width)) }
    private var saved_h: Int { Int((RecordingController.shared.recordingPixelSize.height)) }

    func stopRecording() {
        isPaused = false
        RecordingController.shared.stop()
    }

    /// Transcribe a meeting recording on-device and build notes (summary, tasks, key points),
    /// then show them and save a Markdown copy next to the recording.
    func generateMeetingNotes(url: URL, title: String, date: Date,
                              hasParticipants: Bool, hasYou: Bool,
                              preLines: [TranscriptLine] = []) {
        guard !generatingNotes else { return }
        generatingNotes = true
        let usingCaptions = !preLines.isEmpty
        Toast.show(usingCaptions ? "Building notes from Meet captions…" : "Transcribing meeting on-device…",
                   symbol: usingCaptions ? "captions.bubble.fill" : "waveform")
        Task {
            do {
                let lines: [TranscriptLine]
                if usingCaptions {
                    lines = preLines            // named, timestamped lines straight from Meet
                } else {
                    lines = try await MeetingTranscriber.transcribe(
                        url: url, hasParticipants: hasParticipants, hasYou: hasYou,
                        progress: { msg in Task { @MainActor in Toast.show(msg, symbol: "waveform") } })
                }
                let notes = MeetingAnalyzer.analyze(lines)
                let doc = MeetingDoc(title: title, date: date, notes: notes,
                                     lines: lines, recordingURL: url)
                // Save a sidecar .md next to the recording.
                let sidecar = url.deletingPathExtension().appendingPathExtension("md")
                try? doc.markdown().write(to: sidecar, atomically: true, encoding: .utf8)
                generatingNotes = false
                if lines.isEmpty {
                    Toast.show("No speech recognized in this recording", symbol: "waveform.slash")
                } else {
                    Toast.show("Meeting notes ready", symbol: "person.2.wave.2.fill")
                }
                MeetingNotesWindowController.present(doc)
            } catch {
                generatingNotes = false
                Toast.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// Generate notes for an existing recording already in the library.
    func generateNotesForExisting(url: URL, title: String, date: Date) {
        generateMeetingNotes(url: url, title: title, date: date,
                             hasParticipants: true, hasYou: true)
    }

    /// Grab a still of the recorded area without stopping the recording.
    private func snapshotDuringRecording(rect: CGRect?, on screen: NSScreen) {
        Task {
            do {
                let result: CaptureResult
                if let rect { result = try await CaptureController.captureRegion(rect, on: screen) }
                else { result = try await CaptureController.captureFullScreen(at: NSEvent.mouseLocation) }
                if library.saveImage(result.image) != nil {
                    Toast.show("Screenshot saved to library", symbol: "camera.fill")
                }
            } catch { Toast.show("Screenshot failed", symbol: "exclamationmark.triangle.fill") }
        }
    }

    /// Scrolling capture: drag out a region, then auto-scroll + stitch into one tall image.
    func scrollingCapture() {
        hideOwnWindows()
        selector = RegionSelector()
        selector?.present(mode: .region) { [weak self] outcome in
            guard let self else { return }
            guard case let .region(screen, rect) = outcome else { self.restoreOwnWindows(); return }
            if !ScrollCaptureController.accessibilityTrusted() {
                Toast.show("Allow Accessibility for Snappilot so it can auto-scroll", symbol: "hand.raised.fill")
                ScrollCaptureController.promptAccessibility()
            }
            Toast.show("Scrolling capture — keep the window still…", symbol: "arrow.down.doc")
            ScrollCaptureController.shared.start(region: rect, on: screen) { [weak self] image in
                guard let self else { return }
                guard let image else {
                    self.restoreOwnWindows()
                    Toast.show("Scrolling capture failed", symbol: "exclamationmark.triangle.fill")
                    return
                }
                let selection = CaptureSelection(rect: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                                                 displayID: CaptureController.screenNumber(screen), scale: 1)
                self.openEditor(with: CaptureResult(image: image, selection: selection))
                Toast.show("Scrolling capture saved", symbol: "arrow.down.doc.fill")
            }
        }
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
        if let editor {
            // Reuse the one editor window — replace its content (saving the old first).
            editor.load(image: result.image, recordID: record?.id)
        } else {
            let controller = EditorWindowController(image: result.image, appState: self, recordID: record?.id)
            controller.onClose = { [weak self] _ in self?.editor = nil }
            editor = controller
            controller.showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
