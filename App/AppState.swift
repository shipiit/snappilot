import AppKit
import UniformTypeIdentifiers
import SwiftUI
@preconcurrency import ScreenCaptureKit
import AVFoundation
import SnapCore

/// Coordinates capture → editor → library. Owned by the app; injected into views.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { self == .system ? "System" : self == .light ? "Light" : "Dark" }
    var symbol: String { self == .system ? "circle.lefthalf.filled" : self == .light ? "sun.max" : "moon" }
}

/// A reusable capture recipe, similar to Snagit's custom capture presets.
enum CapturePresetAction: String, CaseIterable, Codable, Identifiable {
    case region, window, fullScreen, text, scrolling, recordRegion, recordScreen
    var id: String { rawValue }
    var title: String {
        switch self {
        case .region: return "Region"
        case .window: return "Window"
        case .fullScreen: return "Full Screen"
        case .text: return "Grab Text (OCR)"
        case .scrolling: return "Scrolling Capture"
        case .recordRegion: return "Record Region"
        case .recordScreen: return "Record Screen"
        }
    }
    var symbol: String {
        switch self {
        case .region: return "crop"
        case .window: return "macwindow"
        case .fullScreen: return "display"
        case .text: return "text.viewfinder"
        case .scrolling: return "arrow.down.doc"
        case .recordRegion: return "record.circle"
        case .recordScreen: return "rectangle.badge.record"
        }
    }
}

struct CapturePreset: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var name: String
    var action: CapturePresetAction
    var delay: Int = 0
    var recordMic: Bool = false
    var recordCamera: Bool = false

    static let defaults: [CapturePreset] = [
        CapturePreset(name: "Quick region", action: .region),
        CapturePreset(name: "Documentation shot", action: .region, delay: 3),
        CapturePreset(name: "Text to clipboard", action: .text),
        CapturePreset(name: "Screen demo", action: .recordScreen, recordMic: true),
    ]
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let library = LibraryStore()

    @Published var ocrLanguages: [String] = Preference.value("pref.ocrLanguages", default: ["en-US"]) {
        didSet { Preference.set(ocrLanguages, for: "pref.ocrLanguages") }
    }
    @Published var recordSystemAudio: Bool = Preference.value("pref.recordSystemAudio", default: true) {
        didSet { Preference.set(recordSystemAudio, for: "pref.recordSystemAudio") }
    }
    @Published var recordMic: Bool = Preference.value("pref.recordMic", default: false) {
        didSet { Preference.set(recordMic, for: "pref.recordMic") }
    }
    @Published var recordNoiseCancellation: Bool = Preference.value("pref.recordNoiseCancellation", default: true) {
        didSet { Preference.set(recordNoiseCancellation, for: "pref.recordNoiseCancellation") }
    }
    @Published var recordCamera: Bool = Preference.value("pref.recordCamera", default: false) {
        didSet { Preference.set(recordCamera, for: "pref.recordCamera") }
    }
    @Published var recordWebcamEffect: WebcamBackgroundEffect = Preference.value("pref.recordWebcamEffect", default: WebcamBackgroundEffect.none) {
        didSet { Preference.set(recordWebcamEffect, for: "pref.recordWebcamEffect") }
    }
    @Published var recordCursor: Bool = Preference.value("pref.recordCursor", default: true) {
        didSet { Preference.set(recordCursor, for: "pref.recordCursor") }
    }
    @Published var recordCursorHighlight: Bool = Preference.value("pref.recordCursorHighlight", default: false) {
        didSet { Preference.set(recordCursorHighlight, for: "pref.recordCursorHighlight") }
    }
    @Published var recordCountdown: Bool = Preference.value("pref.recordCountdown", default: true) {
        didSet { Preference.set(recordCountdown, for: "pref.recordCountdown") }
    }
    @Published var recordQuality: RecordQuality = Preference.value("pref.recordQuality", default: RecordQuality.balanced) {
        didSet { Preference.set(recordQuality, for: "pref.recordQuality") }
    }
    @Published var captureDelay: Int = Preference.value("pref.captureDelay", default: 0) {
        didSet { Preference.set(captureDelay, for: "pref.captureDelay") }
    }
    /// Format new captures are saved in to the library (issue #2).
    @Published var captureFormat: CaptureFormat = Preference.value("pref.captureFormat", default: CaptureFormat.png) {
        didSet { Preference.set(captureFormat, for: "pref.captureFormat") }
    }
    /// JPEG/HEIC quality, 0.1…1.
    @Published var captureQuality: Double = Preference.value("pref.captureQuality", default: CaptureEncoder.defaultQuality) {
        didSet { Preference.set(captureQuality, for: "pref.captureQuality") }
    }
    @Published var afterCapture: AfterCaptureAction = Preference.value("pref.afterCapture", default: AfterCaptureAction.openEditor) {
        didSet { Preference.set(afterCapture, for: "pref.afterCapture") }
    }
    /// Copy every screenshot to the clipboard as well (when the editor opens).
    @Published var alsoCopyCapture: Bool = Preference.value("pref.alsoCopyCapture", default: false) {
        didSet { Preference.set(alsoCopyCapture, for: "pref.alsoCopyCapture") }
    }
    @Published var captureSound: Bool = Preference.value("pref.captureSound", default: true) {
        didSet { Preference.set(captureSound, for: "pref.captureSound") }
    }
    @Published var captureCursor: Bool = Preference.value(CaptureSettings.cursorKey, default: false) {
        didSet { Preference.set(captureCursor, for: CaptureSettings.cursorKey) }
    }
    @Published var captureWindowShadow: Bool = Preference.value(CaptureSettings.shadowKey, default: true) {
        didSet { Preference.set(captureWindowShadow, for: CaptureSettings.shadowKey) }
    }
    @Published var captureMagnifier: Bool = Preference.value("pref.captureMagnifier", default: true) {
        didSet { Preference.set(captureMagnifier, for: "pref.captureMagnifier") }
    }
    /// Open the player when a (non-meeting) recording finishes.
    @Published var openPlayerAfterRecording: Bool = Preference.value("pref.openPlayerAfterRecording", default: true) {
        didSet { Preference.set(openPlayerAfterRecording, for: "pref.openPlayerAfterRecording") }
    }
    @Published var capturePresets: [CapturePreset] = []
    @Published var isRecording = false
    @Published var isStepRecording = false
    @Published var isPaused = false
    @Published var generatingNotes = false
    @Published var selectedNoteID: String?
    @Published var appearance: AppearanceMode =
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "") ?? .system {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearanceMode")
            applyAppearance()
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "capturePresets.v1"),
           let saved = try? JSONDecoder().decode([CapturePreset].self, from: data), !saved.isEmpty {
            capturePresets = saved
        } else {
            capturePresets = CapturePreset.defaults
        }
    }

    func saveCapturePresets() {
        if let data = try? JSONEncoder().encode(capturePresets) {
            UserDefaults.standard.set(data, forKey: "capturePresets.v1")
        }
    }

    /// Mic/camera settings to put back after a preset's recording, so presets don't
    /// permanently change the saved defaults.
    private var presetOverride: (mic: Bool, camera: Bool)?

    func runPreset(_ preset: CapturePreset) {
        restorePresetOverride()
        let previousDelay = captureDelay
        captureDelay = preset.delay
        defer { captureDelay = previousDelay } // preset delay is one-shot
        if preset.action == .recordRegion || preset.action == .recordScreen {
            presetOverride = (recordMic, recordCamera)
            recordMic = preset.recordMic
            recordCamera = preset.recordCamera
        }
        switch preset.action {
        case .region: captureRegion()
        case .window: captureWindow()
        case .fullScreen: captureFullScreen()
        case .text: grabText()
        case .scrolling: scrollingCapture()
        case .recordRegion: recordRegion()
        case .recordScreen: recordScreen()
        }
    }

    private func restorePresetOverride() {
        guard let saved = presetOverride else { return }
        presetOverride = nil
        recordMic = saved.mic
        recordCamera = saved.camera
    }

    /// Force the app's light/dark appearance, or follow the system.
    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

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

    func captureRegion() { withCaptureDelay { self.runRegion { result in self.finishCapture(with: result) } } }

    func captureFullScreen() { withCaptureDelay { self.captureFullScreenNow() } }

    private func captureFullScreenNow() {
        hideOwnWindows()
        Task {
            do {
                try? await Task.sleep(for: .milliseconds(150))   // let our window vanish
                let result = try await CaptureController.captureFullScreen(at: NSEvent.mouseLocation)
                finishCapture(with: result)
            } catch {
                restoreOwnWindows()
                Toast.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func captureWindow() { withCaptureDelay { self.captureWindowNow() } }

    private func captureWindowNow() {
        guard !RegionSelector.isPresenting else { return }   // ignore duplicate triggers
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
                    self.finishCapture(with: CaptureResult(image: image, selection: sel))
                } catch {
                    self.restoreOwnWindows()
                    Toast.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    /// Grab text: select a region, OCR it, copy to clipboard.
    func grabText() { withCaptureDelay { self.grabTextNow() } }

    func captureWebcamPhoto() {
        Toast.show("Capturing webcam photo…", symbol: "camera.fill")
        WebcamPhotoCapture.shared.capture { [weak self] image in
            guard let self, let image else {
                Toast.show("Couldn't capture webcam photo", symbol: "video.slash.fill"); return
            }
            let selection = CaptureSelection(rect: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                                             displayID: 0, scale: 1)
            self.finishCapture(with: CaptureResult(image: image, selection: selection))
        }
    }

    func startStepRecorder() {
        guard !isStepRecording else { StepRecorder.shared.stop(); return }
        if !ScrollCaptureController.accessibilityTrusted() {
            Toast.show("Allow Accessibility so Step Recorder can detect clicks", symbol: "hand.raised.fill")
            ScrollCaptureController.promptAccessibility()
        }
        hideOwnWindows(); isStepRecording = true
        StepRecorder.shared.start { [weak self] guide in
            guard let self else { return }
            self.isStepRecording = false
            guard let guide else {
                self.restoreOwnWindows(); Toast.show("No steps captured", symbol: "number.square"); return
            }
            let selection = CaptureSelection(rect: CGRect(x: 0, y: 0, width: guide.width, height: guide.height),
                                             displayID: 0, scale: 1)
            self.finishCapture(with: CaptureResult(image: guide, selection: selection))
            Toast.show("Step guide ready", symbol: "list.number")
        }
    }

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
        guard !RegionSelector.isPresenting else { return }   // ignore duplicate triggers
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
                    WebcamOverlay.shared.show(in: globalRect, effect: recordWebcamEffect)
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
            self.restorePresetOverride()
            RecordingHUD.shared.hide()
            WebcamOverlay.shared.hide()
            RecordingFrame.shared.hide()
            CursorHighlight.shared.stop()
            self.restoreOwnWindows()
            guard let url else { Toast.show("Recording failed", symbol: "exclamationmark.triangle.fill"); return }
            let wasMeeting = self.meetingMode
            self.meetingMode = false
            let captionLines = wasMeeting ? MeetCaptionReader.shared.stop() : []
            let size = (width: self.saved_w, height: self.saved_h)
            // Meetings keep mic and system audio apart so notes can tell "You" from participants.
            guard !wasMeeting else {
                self.saveFinishedRecording(url, wasMeeting: true, captionLines: captionLines, size: size)
                return
            }
            Task { @MainActor in
                if (try? await AudioMixdown.audioTrackCount(of: url)) ?? 0 > 1 {
                    Toast.show("Finishing recording…", symbol: "waveform")
                }
                do { try await AudioMixdown.mixInPlace(url) } catch {
                    Toast.show("Saved with separate audio tracks (mixdown failed)", symbol: "exclamationmark.triangle.fill")
                }
                self.saveFinishedRecording(url, wasMeeting: false, captionLines: [], size: size)
            }
        }
        startRecordingStream(rec: rec, rect: rect, on: screen)
    }

    private func saveFinishedRecording(_ url: URL, wasMeeting: Bool, captionLines: [TranscriptLine],
                                       size: (width: Int, height: Int)) {
        if let saved = self.library.saveVideo(from: url, width: size.width, height: size.height) {
            Toast.show("Recording saved", symbol: "video.fill")
            let fileURL = self.library.fileURL(for: saved)
            if wasMeeting {
                self.generateMeetingNotes(url: fileURL, title: saved.title,
                                          date: saved.createdAt,
                                          hasParticipants: self.lastHadParticipants,
                                          hasYou: self.lastHadYou,
                                          preLines: captionLines, recordID: saved.id)
            } else if openPlayerAfterRecording {
                VideoPreviewWindowController.present(url: fileURL, title: saved.title)
            }
        } else {
            Toast.show("Couldn't save recording", symbol: "exclamationmark.triangle.fill")
        }
    }

    private func startRecordingStream(rec: RecordingController, rect: CGRect?, on screen: NSScreen) {
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
                restorePresetOverride()
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
                              preLines: [TranscriptLine] = [], recordID: String? = nil) {
        guard !generatingNotes else {
            Toast.show("Already generating notes — please wait…", symbol: "hourglass")
            return
        }
        generatingNotes = true
        let usingCaptions = !preLines.isEmpty
        Toast.show(usingCaptions ? "Building notes from Meet captions…" : "Transcribing on-device — this can take a few minutes…",
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
                // Save a sidecar .md (portable) + .notes.json (reopenable) next to the recording,
                // and index the transcript so the meeting is searchable by what was said.
                let sidecar = url.deletingPathExtension().appendingPathExtension("md")
                try? doc.markdown().write(to: sidecar, atomically: true, encoding: .utf8)
                if let recordID, let record = library.records.first(where: { $0.id == recordID }) {
                    library.saveNotes(doc, for: record)
                    library.setOCRText(id: record.id, doc.searchText())
                }
                generatingNotes = false
                let speakerCount = Set(lines.map { $0.speaker }).count
                if lines.isEmpty {
                    Toast.show("No speech recognized in this recording", symbol: "waveform.slash")
                } else if usingCaptions {
                    Toast.show("Meeting notes ready — named \(speakerCount) speaker\(speakerCount == 1 ? "" : "s") from Meet captions",
                               symbol: "captions.bubble.fill")
                } else {
                    Toast.show("Meeting notes ready (You / Participants — no Meet captions found)",
                               symbol: "person.2.wave.2.fill")
                }
                MeetingNotesWindowController.present(doc)
            } catch {
                generatingNotes = false
                Toast.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
                // If Speech Recognition permission is the blocker, open the right settings pane.
                if case MeetingTranscribeError.notAuthorized = error {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    /// Generate notes for an existing recording already in the library.
    func generateNotesForExisting(url: URL, title: String, date: Date, recordID: String? = nil) {
        generateMeetingNotes(url: url, title: title, date: date,
                             hasParticipants: true, hasYou: true, recordID: recordID)
    }

    /// Transcribe a recording by its file URL (used from the video player). Finds the matching
    /// library record so notes persist, then generates fresh meeting notes.
    func transcribeRecording(url: URL, fallbackTitle: String) {
        let record = library.records.first { library.fileURL(for: $0).path == url.path }
        generateNotesForExisting(url: url,
                                 title: record?.title ?? fallbackTitle,
                                 date: record?.createdAt ?? Date(),
                                 recordID: record?.id)
    }

    /// Reopen already-generated notes instantly, or generate them if none exist yet.
    func openMeetingNotes(for record: CaptureRecord) {
        if let doc = library.loadNotes(for: record) {
            MeetingNotesWindowController.present(doc)
        } else {
            generateNotesForExisting(url: library.fileURL(for: record),
                                     title: record.title, date: record.createdAt, recordID: record.id)
        }
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
        guard !RegionSelector.isPresenting else { return }   // ignore duplicate triggers
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
                self.finishCapture(with: CaptureResult(image: image, selection: selection))
                Toast.show("Scrolling capture saved", symbol: "arrow.down.doc.fill")
            }
        }
    }

    /// Hotkey-friendly toggles: start if idle, stop if already recording.
    func toggleRecordRegion() { isRecording ? stopRecording() : recordRegion() }
    func toggleRecordScreen() { isRecording ? stopRecording() : recordScreen() }

    // MARK: Helpers

    private func runRegion(_ handler: @escaping (CaptureResult) -> Void) {
        guard !RegionSelector.isPresenting else { return }   // ignore duplicate triggers
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

    /// Every screenshot ends here: it's saved to the library at once, then handled per the
    /// "After capture" setting (open the editor, copy to the clipboard, or just save).
    private func finishCapture(with result: CaptureResult) {
        restoreOwnWindows()
        if captureSound { NSSound(named: "Tink")?.play() }
        let record = library.saveImage(result.image)
        switch afterCapture {
        case .openEditor:
            if alsoCopyCapture { Exporter.copyToPasteboard(result.image) }
            // The editor overwrites the saved file with annotations when you press Done.
            openEditor(image: result.image, recordID: record?.id)
            NSApp.activate(ignoringOtherApps: true)
        case .copyToClipboard:
            Exporter.copyToPasteboard(result.image)
            Toast.show("Copied to clipboard · saved to library", symbol: "doc.on.clipboard.fill")
        case .saveOnly:
            Toast.show(record == nil ? "Couldn't save capture" : "Saved to library",
                       symbol: record == nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
        }
    }

    /// Reopen a saved library image in the annotation editor. Saving updates the same
    /// capture instead of creating a duplicate record.
    func annotateAgain(_ record: CaptureRecord) {
        guard record.kind == .image,
              let image = NSImage(contentsOf: library.fileURL(for: record)),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Toast.show("Couldn't open this capture", symbol: "exclamationmark.triangle.fill")
            return
        }
        openEditor(image: cgImage, recordID: record.id, project: library.loadProject(for: record))
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Files from Finder (issue #1)

    static let openableTypes: [UTType] = [.png, .jpeg, .heic, .tiff, .mpeg4Movie, .quickTimeMovie]

    /// File › Open… — pick images or videos already on the Mac.
    func openFilesFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.openableTypes
        panel.allowsMultipleSelection = true
        panel.message = "Choose an image to annotate or a video to play"
        guard panel.runModal() == .OK else { return }
        openExternal(panel.urls)
    }

    /// Open files handed to Snappilot (Open With, Dock drop, File › Open). Images open in the
    /// editor — Done adds the result to the library and leaves the original untouched; videos
    /// open in the player, where they can be trimmed and annotated.
    func openExternal(_ urls: [URL]) {
        for url in urls {
            let type = UTType(filenameExtension: url.pathExtension)
            if type?.conforms(to: .movie) == true {
                VideoPreviewWindowController.present(url: url, title: url.deletingPathExtension().lastPathComponent)
            } else if let image = NSImage(contentsOf: url),
                      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                openEditor(image: cgImage, recordID: nil, externalSource: url)
            } else {
                Toast.show("Couldn't open \(url.lastPathComponent)", symbol: "exclamationmark.triangle.fill")
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openEditor(image: CGImage, recordID: String?, externalSource: URL? = nil,
                            project: EditorProject.Loaded? = nil) {
        if let editor {
            editor.load(image: image, recordID: recordID, project: project, externalSource: externalSource)
        } else {
            let controller = EditorWindowController(image: image, appState: self, recordID: recordID,
                                                    project: project, externalSource: externalSource)
            controller.onClose = { [weak self] _ in self?.editor = nil }
            editor = controller
            controller.showWindow(nil)
        }
    }

    func annotateLatestImage() {
        guard let record = library.records.first(where: { $0.kind == .image }) else {
            Toast.show("No image captures yet", symbol: "photo")
            return
        }
        annotateAgain(record)
    }

    func shareLatestCapture() {
        guard let record = library.records.first else {
            Toast.show("No captures yet", symbol: "square.and.arrow.up"); return
        }
        SystemShare.file(library.fileURL(for: record))
    }

    func selectEditorTool(_ tool: Tool?) {
        guard editor != nil else {
            Toast.show("Open or capture an image first", symbol: "pencil.and.outline"); return
        }
        if let tool {
            NotificationCenter.default.post(name: .snappilotSelectTool, object: tool.rawValue)
        } else {
            NotificationCenter.default.post(name: .snappilotSelectMode, object: nil)
        }
        editor?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func undoEditor() { editor?.undo() }
    func redoEditor() { editor?.redo() }
}
