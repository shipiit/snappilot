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

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 236)
            Rectangle().fill(Theme.stroke).frame(width: 1)
            content
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(Theme.appBG)
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
            navItem(.collections, badge: nil)

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
            case .collections: collectionsPlaceholder
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
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 6), spacing: 14) {
                    captureCard("Region", "Capture a specific area of your screen", "crop", hotkeys.display(.captureRegion), [C("#3B82F6"), C("#2563EB")]) { app.captureRegion() }
                    captureCard("Window", "Capture a specific application window", "macwindow", hotkeys.display(.captureWindow), [C("#22B8CF"), C("#0E8FA8")]) { app.captureWindow() }
                    captureCard("Full Screen", "Capture your entire screen", "display", hotkeys.display(.captureFull), [C("#8B5CF6"), C("#6D28D9")]) { app.captureFullScreen() }
                    captureCard("Grab Text (OCR)", "Extract text from any area", "text.viewfinder", hotkeys.display(.grabText), [C("#22C55E"), C("#16A34A")]) { app.grabText() }
                    captureCard("Record Region", "Record a specific area", "record.circle", hotkeys.display(.recordRegion), [C("#F97316"), C("#EF4444")]) { app.toggleRecordRegion() }
                    captureCard("Record Screen", "Record your entire screen", "rectangle.badge.record", hotkeys.display(.recordScreen), [C("#EC4899"), C("#DB2777")]) { app.toggleRecordScreen() }
                }

                recordingBar

                HStack {
                    sectionTitle("Recent Captures")
                    Spacer()
                    searchField.frame(width: 280)
                    Button { exportPDF() } label: { Label("PDF", systemImage: "doc.richtext") }
                        .buttonStyle(.bordered).controlSize(.large).help("Export images to a PDF")
                    Button { newFolder() } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                        .buttonStyle(.bordered).controlSize(.large)
                }
                galleryGrid(records: Array(filtered(library.records).prefix(8)))
            }
            .padding(28)
        }
    }

    private var recordingBar: some View {
        HStack(spacing: 26) {
            optionToggle("System Audio", "waveform", isOn: $app.recordSystemAudio)
            optionToggle("Microphone", "mic.fill", isOn: $app.recordMic)
            optionToggle("Camera", "camera.fill", isOn: $app.recordCamera)
            optionToggle("Cursor", "cursorarrow", isOn: $app.recordCursor)
            optionToggle("Countdown", "timer", isOn: $app.recordCountdown)
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars").foregroundStyle(.secondary).font(.system(size: 13))
                Text("Quality").font(.system(size: 13)).foregroundStyle(.primary).lineLimit(1).fixedSize()
                Picker("", selection: $app.recordQuality) {
                    ForEach(RecordQuality.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().fixedSize().help("Higher quality = larger file")
            }
            .fixedSize()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Theme.panelBG, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 1))
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
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                    .frame(height: 30)
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text(desc).font(.system(size: 10)).foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                Text(shortcut).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.white.opacity(0.18), in: Capsule())
            }
            .frame(maxWidth: .infinity).frame(height: 168)
            .padding(.vertical, 14)
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

    private var collectionsPlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder").font(.system(size: 54)).foregroundStyle(.tertiary)
            Text("Collections").font(.title2.bold()).foregroundStyle(.primary)
            Text("Group captures into collections. Use “New Folder” on the Dashboard to make one in your library.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            Button { app.openLibraryFolder() } label: { Label("Open library folder", systemImage: "folder") }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func newFolder() {
        let url = library.root.appendingPathComponent("New Folder \(library.records.count + 1)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    /// Export the images currently in view into a single multi-page PDF.
    private func exportPDF() {
        let images = filtered(library.records).filter { $0.kind == .image }.map { library.fileURL(for: $0) }
        guard !images.isEmpty else { Toast.show("No images to export", symbol: "doc.richtext"); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Snappilot.pdf"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        if PDFExporter.export(imageURLs: images, to: dest) {
            Toast.show("PDF exported · \(images.count) page\(images.count == 1 ? "" : "s")", symbol: "doc.richtext")
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } else {
            Toast.show("PDF export failed", symbol: "exclamationmark.triangle.fill")
        }
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
                    if record.kind == .image { Button("Copy Image") { copyImage() } }
                    Button(record.favorite ? "Remove from Favorites" : "Add to Favorites") { library.toggleFavorite(id: record.id) }
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
