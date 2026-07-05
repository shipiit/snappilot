import SwiftUI
import SnapCore

private func C(_ hex: String) -> Color { Color(nsColor: nsColor(fromHex: hex)) }

enum HomeSection: String, CaseIterable, Identifiable {
    case dashboard, library, favorites, collections
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .library: return "Library"
        case .favorites: return "Favorites"
        case .collections: return "Collections"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: return "house"
        case .library: return "square.stack"
        case .favorites: return "star"
        case .collections: return "folder"
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var hotkeys = HotkeyStore.shared
    @ObservedObject private var library = AppState.shared.library
    @Environment(\.openSettings) private var openSettings

    @State private var section: HomeSection = .dashboard
    @State private var query = ""
    @State private var showRecOptions = false
    @State private var showPDFSheet = false
    @State private var pdfSelection: Set<String> = []
    @State private var openCollection: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 236)
            Rectangle().fill(Theme.stroke).frame(width: 1)
            content
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(Theme.appBG)
        .sheet(isPresented: $showPDFSheet) { pdfSheet }
    }

    // MARK: Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(C("#5661F6"))
                    .frame(width: 42, height: 42)
                    .overlay(Image(systemName: "camera.viewfinder").foregroundStyle(.white).font(.system(size: 19, weight: .semibold)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Snappilot").font(.system(size: 17, weight: .bold)).foregroundStyle(.primary)
                    Text("Capture · Annotate · Record · OCR").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 22)

            navItem(.dashboard, badge: nil)
            navItem(.library, badge: library.records.count)
            navItem(.favorites, badge: library.favorites.isEmpty ? nil : library.favorites.count)
            navItem(.collections, badge: library.collections.isEmpty ? nil : library.collections.count)

            Divider().padding(.vertical, 8).padding(.horizontal, 14)

            navButton("gearshape", "Settings") { openSettings() }
            navButton("keyboard", "Shortcuts") { openSettings() }
            navButton("questionmark.circle", "Help & Guide") { WelcomeWindowController.present(app: app) }

            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebarBG)
    }

    private func navItem(_ s: HomeSection, badge: Int?) -> some View {
        let selected = section == s
        return Button { withAnimation(.easeInOut(duration: 0.18)) { section = s; query = "" } } label: {
            HStack(spacing: 12) {
                Image(systemName: s.icon).font(.system(size: 15)).frame(width: 20)
                Text(s.title).font(.system(size: 14, weight: selected ? .semibold : .regular))
                Spacer()
                if let badge {
                    Text("\(badge)").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .background(Theme.chipBG, in: Capsule())
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(selected ? Theme.selectedNav : .clear, in: RoundedRectangle(cornerRadius: 9))
            .overlay(alignment: .leading) {
                if selected { Capsule().fill(C("#3B82F6")).frame(width: 3, height: 20).offset(x: -2) }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }

    private func navButton(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15)).frame(width: 20)
                Text(title).font(.system(size: 14))
                Spacer()
            }
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }

    // MARK: Content
    @ViewBuilder private var content: some View {
        Group {
            switch section {
            case .dashboard: dashboard
            case .library: gallerySection(title: "Library", records: filtered(library.records))
            case .favorites: gallerySection(title: "Favorites", records: filtered(library.favorites))
            case .collections: collectionsView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(section)
        .transition(.opacity)
    }

    private func filtered(_ recs: [CaptureRecord]) -> [CaptureRecord] {
        query.isEmpty ? recs : recs.filter { CaptureLibrary.matches($0, query: query) }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header(title: "Dashboard", subtitle: "Capture, annotate and organize your work with ease.")

                HStack {
                    sectionTitle("Quick Capture")
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "timer").foregroundStyle(.secondary).font(.system(size: 13))
                        Text("Delay").font(.system(size: 13)).foregroundStyle(.primary)
                        Picker("", selection: $app.captureDelay) {
                            Text("Off").tag(0); Text("3s").tag(3); Text("5s").tag(5)
                        }.labelsHidden().fixedSize().help("Countdown before a screenshot")
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        captureCard("Region", "Capture a specific area of your screen", "crop", hotkeys.display(.captureRegion), [C("#3B82F6"), C("#2563EB")]) { app.captureRegion() }
                        captureCard("Window", "Capture a specific application window", "macwindow", hotkeys.display(.captureWindow), [C("#22B8CF"), C("#0E8FA8")]) { app.captureWindow() }
                        captureCard("Full Screen", "Capture your entire screen", "display", hotkeys.display(.captureFull), [C("#8B5CF6"), C("#6D28D9")]) { app.captureFullScreen() }
                        captureCard("Grab Text (OCR)", "Extract text from any area", "text.viewfinder", hotkeys.display(.grabText), [C("#22C55E"), C("#16A34A")]) { app.grabText() }
                        captureCard("Record Region", "Record a specific area", "record.circle", hotkeys.display(.recordRegion), [C("#F97316"), C("#EF4444")]) { app.toggleRecordRegion() }
                        captureCard("Record Screen", "Record your entire screen", "rectangle.badge.record", hotkeys.display(.recordScreen), [C("#EC4899"), C("#DB2777")]) { app.toggleRecordScreen() }
                        captureCard("Record Meeting", "Record a call, then auto-transcribe & get tasks", "person.2.wave.2.fill", app.generatingNotes ? "Working…" : "AI", [C("#6366F1"), C("#4F46E5")]) { app.recordMeeting() }
                    }
                    .padding(.horizontal, 1).padding(.bottom, 6)
                }

                recordingBar

                HStack {
                    sectionTitle("Recent Captures")
                    Spacer()
                    searchField.frame(width: 280)
                    Button { openPDFPicker() } label: { Label("PDF", systemImage: "doc.richtext") }
                        .buttonStyle(.bordered).controlSize(.large).help("Pick images and export a PDF")
                    Button { newFolder() } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                        .buttonStyle(.bordered).controlSize(.large)
                }
                galleryGrid(records: Array(filtered(library.records).prefix(8)))
            }
            .padding(28)
        }
    }

    private var enabledSummary: [(String, String)] {
        var out: [(String, String)] = []
        if app.recordSystemAudio { out.append(("Audio", "speaker.wave.2.fill")) }
        if app.recordMic { out.append(("Mic", "mic.fill")) }
        if app.recordCamera { out.append(("Camera", "web.camera.fill")) }
        if app.recordCursorHighlight { out.append(("Highlight", "cursorarrow.rays")) }
        if app.recordCountdown { out.append(("Countdown", "timer")) }
        return out
    }

    private var recordingBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle").foregroundStyle(.red).font(.system(size: 14))
            Text("Recording").font(.system(size: 13, weight: .medium))
            ForEach(enabledSummary, id: \.0) { title, icon in
                HStack(spacing: 4) {
                    Image(systemName: icon).font(.system(size: 10))
                    Text(title).font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.chipBG, in: Capsule())
            }
            if enabledSummary.isEmpty {
                Text("screen only").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Spacer()
            Text(app.recordQuality.title).font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.chipBG, in: Capsule())
            Button { showRecOptions.toggle() } label: {
                Label("Customize", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showRecOptions, arrowEdge: .bottom) { optionsPopover }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Theme.panelBG, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 1))
    }

    private var optionsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recording Options").font(.headline)
            popoverToggle("System audio", "speaker.wave.2.fill", $app.recordSystemAudio)
            popoverToggle("Microphone", "mic.fill", $app.recordMic)
            if app.recordMic {
                popoverToggle("Noise cancellation", "waveform.badge.mic", $app.recordNoiseCancellation)
                    .padding(.leading, 18)
            }
            popoverToggle("Camera overlay", "web.camera.fill", $app.recordCamera)
            popoverToggle("Show cursor", "cursorarrow", $app.recordCursor)
            popoverToggle("Cursor highlight & clicks", "cursorarrow.rays", $app.recordCursorHighlight)
            popoverToggle("Countdown before recording", "timer", $app.recordCountdown)
            Divider()
            HStack {
                Image(systemName: "wand.and.stars").foregroundStyle(.secondary).frame(width: 20)
                Text("Quality").font(.callout)
                Spacer()
                Picker("", selection: $app.recordQuality) {
                    ForEach(RecordQuality.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().fixedSize()
            }
        }
        .padding(16).frame(width: 290)
    }

    private func popoverToggle(_ title: String, _ icon: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(binding.wrappedValue ? Color.accentColor : .secondary).frame(width: 20)
            Text(title).font(.callout)
            Spacer()
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }

    private func optionToggle(_ title: String, _ icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).font(.system(size: 13))
            Text(title).font(.system(size: 13)).foregroundStyle(.primary)
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }

    // MARK: Reusable pieces
    private func header(title: String, subtitle: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 28, weight: .bold)).foregroundStyle(.primary)
                Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { WelcomeWindowController.present(app: app) } label: { Label("Guide", systemImage: "sparkles") }
                .buttonStyle(.bordered).controlSize(.large)
            Button { openSettings() } label: { Label("Settings", systemImage: "gearshape") }
                .buttonStyle(.bordered).controlSize(.large)
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 18, weight: .semibold)).foregroundStyle(.primary)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 13))
            TextField("Search captures & text inside them…", text: $query).textFieldStyle(.plain).font(.system(size: 13))
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.panelBG, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.stroke, lineWidth: 1))
    }

    private func captureCard(_ title: String, _ desc: String, _ icon: String, _ shortcut: String,
                             _ colors: [Color], _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(shortcut).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.white.opacity(0.18), in: Capsule())
                Image(systemName: icon).font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                    .frame(height: 30)
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text(desc).font(.system(size: 10)).foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 150, height: 172)
            .padding(.vertical, 12)
            .background((colors.first ?? Color.accentColor),
                        in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: Gallery
    private func gallerySection(title: String, records: [CaptureRecord]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(title: title, subtitle: title == "Favorites" ? "Your starred captures." : "All your captures, searchable by the text inside them.")
                searchField.frame(maxWidth: 360)
                galleryGrid(records: records)
            }
            .padding(28)
        }
    }

    private func galleryGrid(records: [CaptureRecord]) -> some View {
        Group {
            if records.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 44)).foregroundStyle(.tertiary)
                    Text(query.isEmpty ? "No captures yet" : "No matches").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 18)], spacing: 18) {
                    ForEach(records) { rec in GalleryCard(record: rec, library: library) }
                }
            }
        }
    }

    @ViewBuilder private var collectionsView: some View {
        if let id = openCollection, let coll = library.collections.first(where: { $0.id == id }) {
            collectionDetail(coll)
        } else {
            collectionsGrid
        }
    }

    private var collectionsGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    header(title: "Collections", subtitle: "Group captures together. Drag any capture onto a collection to add it.")
                    Spacer()
                    Button { newCollection() } label: { Label("New Collection", systemImage: "folder.badge.plus") }
                        .buttonStyle(.bordered).controlSize(.large)
                }
                if library.collections.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "folder").font(.system(size: 44)).foregroundStyle(.tertiary)
                        Text("No collections yet").foregroundStyle(.secondary)
                        Text("Make one, then drag captures onto it — or use “Add to Collection” from a capture’s ⋯ menu.")
                            .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 340)
                    }.frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                        ForEach(library.collections) { coll in collectionCard(coll) }
                    }
                }
            }
            .padding(28)
        }
    }

    private func collectionCard(_ coll: Collection) -> some View {
        let members = library.records(in: coll)
        return Button { openCollection = coll.id } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.panelBG).frame(height: 120)
                    if let first = members.first, let img = NSImage(contentsOf: library.fileURL(for: first)) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                            .frame(height: 120).clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "folder").font(.system(size: 34)).foregroundStyle(.tertiary)
                    }
                }
                Text(coll.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                Text("\(coll.count) item\(coll.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename…") { if let n = promptText("Rename collection", coll.name) { library.renameCollection(id: coll.id, to: n) } }
            Button("Delete Collection", role: .destructive) { library.deleteCollection(id: coll.id) }
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            dropRecords(providers, into: coll.id); return true
        }
    }

    private func collectionDetail(_ coll: Collection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Button { openCollection = nil } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless)
                    header(title: coll.name, subtitle: "\(coll.count) item\(coll.count == 1 ? "" : "s") · drag more captures here to add.")
                    Spacer()
                    Button { if let n = promptText("Rename collection", coll.name) { library.renameCollection(id: coll.id, to: n) } } label: {
                        Label("Rename", systemImage: "pencil")
                    }.buttonStyle(.bordered)
                }
                let members = library.records(in: coll)
                if members.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray").font(.system(size: 40)).foregroundStyle(.tertiary)
                        Text("Empty — drag captures here, or use “Add to Collection” from a ⋯ menu.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                        ForEach(members) { rec in
                            GalleryCard(record: rec, library: library)
                                .contextMenu {
                                    Button("Remove from Collection", role: .destructive) {
                                        library.removeFromCollection(coll.id, recordID: rec.id)
                                    }
                                }
                        }
                    }
                }
            }
            .padding(28)
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            dropRecords(providers, into: coll.id); return true
        }
    }

    /// Load dropped record ids and add them to a collection.
    private func dropRecords(_ providers: [NSItemProvider], into collectionID: String) {
        for provider in providers {
            _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
                guard let id = obj as? String else { return }
                Task { @MainActor in library.addToCollection(collectionID, recordID: id) }
            }
        }
    }

    private func newCollection() {
        if let name = promptText("New collection", "") { library.createCollection(name: name) }
    }

    /// Simple single-field prompt via NSAlert.
    private func promptText(_ title: String, _ initial: String) -> String? {
        let alert = NSAlert(); alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let t = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func newFolder() {
        let url = library.root.appendingPathComponent("New Folder \(library.records.count + 1)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    private var pdfImages: [CaptureRecord] { library.records.filter { $0.kind == .image } }

    private func openPDFPicker() {
        guard !pdfImages.isEmpty else { Toast.show("No images to export", symbol: "doc.richtext"); return }
        pdfSelection = Set(pdfImages.map { $0.id })   // preselect all
        showPDFSheet = true
    }

    /// A sheet to pick exactly which images go into the PDF.
    private var pdfSheet: some View {
        let imgs = pdfImages
        return VStack(spacing: 0) {
            HStack {
                Text("Select images for PDF").font(.headline)
                Spacer()
                Button(pdfSelection.count == imgs.count ? "Deselect All" : "Select All") {
                    pdfSelection = pdfSelection.count == imgs.count ? [] : Set(imgs.map { $0.id })
                }
            }
            .padding()
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 12)], spacing: 12) {
                    ForEach(imgs) { rec in
                        PDFPickCell(record: rec, library: library, selected: pdfSelection.contains(rec.id)) {
                            if pdfSelection.contains(rec.id) { pdfSelection.remove(rec.id) }
                            else { pdfSelection.insert(rec.id) }
                        }
                    }
                }
                .padding()
            }
            Divider()
            HStack {
                Text("\(pdfSelection.count) of \(imgs.count) selected").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { showPDFSheet = false }.keyboardShortcut(.cancelAction)
                Button("Export PDF") { exportSelectedPDF() }
                    .buttonStyle(.borderedProminent).disabled(pdfSelection.isEmpty).keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 640, height: 540)
    }

    private func exportSelectedPDF() {
        // Preserve library order (newest first) for the chosen images.
        let urls = pdfImages.filter { pdfSelection.contains($0.id) }.map { library.fileURL(for: $0) }
        showPDFSheet = false
        guard !urls.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Snappilot.pdf"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        if PDFExporter.export(imageURLs: urls, to: dest) {
            Toast.show("PDF exported · \(urls.count) page\(urls.count == 1 ? "" : "s")", symbol: "doc.richtext")
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } else {
            Toast.show("PDF export failed", symbol: "exclamationmark.triangle.fill")
        }
    }
}

/// A selectable image thumbnail for the PDF picker.
private struct PDFPickCell: View {
    let record: CaptureRecord
    let library: LibraryStore
    let selected: Bool
    let toggle: () -> Void
    @State private var thumb: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8).fill(Theme.panelBG)
                    .frame(height: 110)
                    .overlay {
                        if let thumb { Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill) }
                        else { Image(systemName: "photo").foregroundStyle(.tertiary) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .white, .black.opacity(0.4))
                    .font(.system(size: 20)).padding(6)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : Theme.stroke, lineWidth: selected ? 2 : 1))
            Text(record.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .task { thumb = NSImage(contentsOf: library.fileURL(for: record)) }
    }
}

/// Ask the user for a tag via a small alert.
@MainActor func promptForTag() -> String? {
    let alert = NSAlert()
    alert.messageText = "Add a tag"
    alert.informativeText = "Tags make captures easy to find later."
    alert.addButton(withTitle: "Add")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
    field.placeholderString = "e.g. bug, design, todo"
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
}

/// A capture thumbnail card with favorite star, format badge, and a ⋯ menu.
private struct GalleryCard: View {
    let record: CaptureRecord
    @ObservedObject var library: LibraryStore
    @EnvironmentObject var app: AppState
    @State private var thumb: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                // A fixed-size box: image fills it and is clipped, so every card is uniform.
                RoundedRectangle(cornerRadius: 12).fill(Theme.panelBG)
                    .frame(maxWidth: .infinity).frame(height: 168)
                    .overlay {
                        if let thumb {
                            Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: record.kind == .video ? "video.fill" : "photo")
                                .font(.system(size: 30)).foregroundStyle(.tertiary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if record.kind == .video {
                    Image(systemName: "play.circle.fill").font(.system(size: 34))
                        .foregroundStyle(.white, .black.opacity(0.4))
                }
                Button { library.toggleFavorite(id: record.id) } label: {
                    Image(systemName: record.favorite ? "star.fill" : "star")
                        .foregroundStyle(record.favorite ? Color.yellow : .white)
                        .padding(7).background(.black.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(8)
            }
            .frame(height: 168)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture { open() }

            Text(record.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
            if !record.tagList.isEmpty {
                HStack(spacing: 4) {
                    ForEach(record.tagList.prefix(4), id: \.self) { tag in
                        Text(tag).font(.system(size: 9, weight: .medium)).foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                }
            }
            HStack(spacing: 8) {
                badge("\(record.width)×\(record.height)")
                badge(record.format)
                Spacer()
                if record.kind == .image {
                    iconButton("doc.on.doc", "Copy image") { copyImage() }
                }
                iconButton("trash", "Move to Trash") { library.moveToTrash(record) }
                Menu {
                    Button("Open") { open() }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([library.fileURL(for: record)]) }
                    if record.kind == .image {
                        Button("Copy Image") { copyImage() }
                        Button("Pin to Screen") { PinBoard.pin(url: library.fileURL(for: record)) }
                    }
                    if record.kind == .video {
                        Button("Meeting Notes (AI)") {
                            app.generateNotesForExisting(url: library.fileURL(for: record),
                                                         title: record.title, date: record.createdAt)
                        }
                    }
                    Button(record.favorite ? "Remove from Favorites" : "Add to Favorites") { library.toggleFavorite(id: record.id) }
                    if !library.collections.isEmpty {
                        Menu("Add to Collection") {
                            ForEach(library.collections) { coll in
                                Button(coll.name) { library.addToCollection(coll.id, recordID: record.id) }
                            }
                        }
                    }
                    Button("Add Tag…") { if let t = promptForTag() { library.addTag(t, to: record.id) } }
                    if !record.tagList.isEmpty {
                        Menu("Remove Tag") {
                            ForEach(record.tagList, id: \.self) { tag in
                                Button(tag) { library.removeTag(tag, from: record.id) }
                            }
                        }
                    }
                    Divider()
                    Button("Move to Trash", role: .destructive) { library.moveToTrash(record) }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton).frame(width: 22)
            }
        }
        .onDrag { NSItemProvider(object: record.id as NSString) }
        .task {
            let url = library.fileURL(for: record)
            if record.kind == .image {
                thumb = NSImage(contentsOf: url)
            } else if let cg = await VideoAnnotator.grabFrame(from: url) {
                thumb = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }
    }

    private func iconButton(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(width: 24, height: 22)
                .background(Theme.chipBG, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain).help(help)
    }

    private func open() {
        let url = library.fileURL(for: record)
        if record.kind == .video {
            VideoPreviewWindowController.present(url: url, title: record.title)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func copyImage() {
        guard let img = NSImage(contentsOf: library.fileURL(for: record)) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
        Toast.show("Copied image")
    }

    private func badge(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Theme.chipBG, in: RoundedRectangle(cornerRadius: 5))
    }
}
