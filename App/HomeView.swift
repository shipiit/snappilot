import SwiftUI
import SnapCore

private func C(_ hex: String) -> Color { Color(nsColor: nsColor(fromHex: hex)) }

enum HomeSection: String, CaseIterable, Identifiable {
    case dashboard, library, favorites, collections, tasks, notes
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .library: return "Library"
        case .favorites: return "Favorites"
        case .collections: return "Collections"
        case .tasks: return "Tasks"
        case .notes: return "Notes"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: return "house"
        case .library: return "square.stack"
        case .favorites: return "star"
        case .collections: return "folder"
        case .tasks: return "checklist"
        case .notes: return "note.text"
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var hotkeys = HotkeyStore.shared
    @ObservedObject private var library = AppState.shared.library
    @Environment(\.openSettings) private var openSettings

    @State private var section: HomeSection = .dashboard
    @State private var sidebarCollapsed = false
    @State private var query = ""
    @State private var showPDFSheet = false
    @State private var pdfSelection: Set<String> = []
    @State private var showBatchSheet = false
    @State private var batchSelection: Set<String> = []
    @State private var batchFormat: ExportFormat = .jpeg
    @State private var batchFramed = false
    @State private var openCollection: String?
    @State private var librarySort: CaptureSort = .newest
    @State private var libraryFilter: CaptureFilter = .all

    var body: some View {
        HStack(spacing: 0) {
            if !sidebarCollapsed {
                Group {
                    if section == .notes {
                        NotesSidebar(library: library, selectedID: $app.selectedNoteID) { section = .dashboard }
                    } else {
                        sidebar
                    }
                }
                .frame(width: 236)
                Rectangle().fill(Theme.stroke).frame(width: 1)
            }
            content
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(Theme.appBG)
        .overlay(alignment: .topLeading) {
            if sidebarCollapsed {
                Button { withAnimation(.easeInOut(duration: 0.15)) { sidebarCollapsed = false } } label: {
                    Image(systemName: "sidebar.left").padding(8)
                        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain).padding(10)
            }
        }
        .sheet(isPresented: $showPDFSheet) { pdfSheet }
        .sheet(isPresented: $showBatchSheet) { batchSheet }
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
                Spacer()
                Button { withAnimation(.easeInOut(duration: 0.15)) { sidebarCollapsed = true } } label: {
                    Image(systemName: "sidebar.left").foregroundStyle(.secondary)
                }.buttonStyle(.borderless).help("Collapse sidebar")
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 22)

            Text("WORKSPACE").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                .padding(.horizontal, 24).padding(.bottom, 3)
            navItem(.dashboard, badge: nil)
            navItem(.library, badge: library.records.count)
            navItem(.favorites, badge: library.favorites.isEmpty ? nil : library.favorites.count)
            navItem(.collections, badge: library.collections.isEmpty ? nil : library.collections.count)
            navItem(.tasks, badge: openTaskCount == 0 ? nil : openTaskCount)
            navItem(.notes, badge: library.notes.isEmpty ? nil : library.notes.count)

            Divider().padding(.vertical, 8).padding(.horizontal, 14)

            Text("QUICK TOOLS").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                .padding(.horizontal, 24).padding(.bottom, 3)
            navButton("pencil.and.outline", "Annotate Latest") { app.annotateLatestImage() }
            navButton("gearshape", "Settings") { openSettings() }
            navButton("keyboard", "Shortcuts") { openSettings() }
            navButton("questionmark.circle", "Help & Guide") { WelcomeWindowController.present(app: app) }

            Spacer()
            sidebarApps
            storageCard
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebarBG)
    }

    /// Compact links to the team's other apps.
    private var sidebarApps: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MORE APPS").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                .padding(.horizontal, 24).padding(.bottom, 3)
            sidebarAppLink("Mac Sweep", "sparkles", "#0EA5E9", "https://github.com/shipiit/mac-sweep/releases/latest")
            sidebarAppLink("KeyVault", "key.fill", "#10B981", "https://github.com/shipiit/keyvault/releases/latest")
        }
        .padding(.bottom, 8)
    }

    private func sidebarAppLink(_ name: String, _ icon: String, _ tint: String, _ url: String) -> some View {
        Button { if let link = URL(string: url) { NSWorkspace.shared.open(link) } } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(hexColor(tint), in: RoundedRectangle(cornerRadius: 6))
                Text(name).font(.system(size: 13))
                Spacer()
                Image(systemName: "arrow.down.circle").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 14).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.horizontal, 10)
        .help("Download \(name)")
    }

    private var storageCard: some View {
        let u = library.storageUsage()
        let total = max(1, u.total)
        func fmt(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
        let segments: [(String, Int64, Color)] = [
            ("Screenshots", u.screenshots, C("#3B82F6")),
            ("Videos", u.videos, C("#EC4899")),
            ("Attachments", u.attachments, C("#22C55E")),
            ("Notes", u.notes, C("#5E6AD2")),
            ("Tasks", u.tasks, C("#E2A03F")),
        ]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Storage", systemImage: "internaldrive").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(fmt(u.total)).font(.system(size: 11, weight: .semibold))
            }
            if let free = freeDiskSpace {
                Text("\(fmt(free)) free on this Mac").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(segments, id: \.0) { seg in
                        Rectangle().fill(seg.2)
                            .frame(width: max(0, geo.size.width * CGFloat(Double(seg.1) / Double(total))))
                    }
                    Rectangle().fill(Theme.stroke)   // remaining track
                }
            }
            .frame(height: 6).clipShape(Capsule())
            VStack(alignment: .leading, spacing: 2) {
                ForEach(segments.filter { $0.1 > 0 }, id: \.0) { seg in
                    HStack(spacing: 5) {
                        Circle().fill(seg.2).frame(width: 6, height: 6)
                        Text(seg.0).font(.system(size: 9)).foregroundStyle(.secondary)
                        Spacer()
                        Text(fmt(seg.1)).font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
            }
            Button { app.openLibraryFolder() } label: {
                Text("Manage Storage").font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.small).padding(.top, 4)
            .help("Open the library folder in Finder")
        }
        .padding(10)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12).padding(.bottom, 12)
    }

    private var freeDiskSpace: Int64? {
        let values = try? library.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
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
            case .dashboard:
                DashboardView(library: library, openSection: { s in withAnimation { section = s } },
                              openSettings: { openSettings() }, export: { openBatchPicker() },
                              exportPDF: { openPDFPicker() },
                              newCollection: { newCollection() })
            case .library: gallerySection(title: "Library", records: filtered(library.records))
            case .favorites: gallerySection(title: "Favorites", records: filtered(library.favorites))
            case .collections: collectionsView
            case .tasks: tasksView
            case .notes: NotesView(library: library, selectedID: $app.selectedNoteID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(section)
        .transition(.opacity)
    }

    private func filtered(_ recs: [CaptureRecord]) -> [CaptureRecord] {
        LibraryQuery.apply(recs, filter: libraryFilter, sort: librarySort, query: query,
                           hasMeetingNotes: library.hasNotes)
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

    // MARK: Gallery
    private func gallerySection(title: String, records: [CaptureRecord]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(title: title, subtitle: title == "Favorites" ? "Your starred captures." : "All your captures, searchable by the text inside them.")
                libraryToolbar
                galleryGrid(records: records)
            }
            .padding(28)
        }
    }

    private var libraryToolbar: some View {
        HStack(spacing: 10) {
            searchField.frame(maxWidth: 360)
            Picker("Filter", selection: $libraryFilter) {
                ForEach(CaptureFilter.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu).frame(width: 140)
            Picker("Sort", selection: $librarySort) {
                ForEach(CaptureSort.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu).frame(width: 140)
            Button { openBatchPicker() } label: { Label("Batch Export", systemImage: "square.stack.3d.up") }
                .buttonStyle(.bordered)
            Spacer()
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 18)], spacing: 18) {
                    ForEach(records) { rec in GalleryCard(record: rec, library: library) }
                }
            }
        }
    }

    // MARK: Tasks (Kanban board)

    private var openTaskCount: Int { library.tasks.filter { $0.status != .done }.count }

    private var tasksView: some View { KanbanView(library: library) }

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
                    if let first = members.first {
                        CollectionCover(url: library.fileURL(for: first), isVideo: first.kind != .image)
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

    private func openBatchPicker() {
        guard !pdfImages.isEmpty else { Toast.show("No images to export", symbol: "photo.stack"); return }
        batchSelection = Set(pdfImages.prefix(12).map { $0.id })
        showBatchSheet = true
    }

    private var batchSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Batch Export").font(.headline)
                Spacer()
                Picker("Format", selection: $batchFormat) {
                    ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
                }.frame(width: 140)
                Toggle("Polished frame", isOn: $batchFramed)
            }.padding()
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 12)], spacing: 12) {
                    ForEach(pdfImages) { record in
                        PDFPickCell(record: record, library: library, selected: batchSelection.contains(record.id)) {
                            if batchSelection.contains(record.id) { batchSelection.remove(record.id) }
                            else { batchSelection.insert(record.id) }
                        }
                    }
                }.padding()
            }
            Divider()
            HStack {
                Text("\(batchSelection.count) selected").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { showBatchSheet = false }.keyboardShortcut(.cancelAction)
                Button("Choose Folder & Export") { exportBatch() }
                    .buttonStyle(.borderedProminent).disabled(batchSelection.isEmpty)
            }.padding()
        }.frame(width: 700, height: 560)
    }

    private func exportBatch() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        var saved = 0
        for record in pdfImages where batchSelection.contains(record.id) {
            // Release each full-size image before decoding the next.
            autoreleasepool {
                guard let image = NSImage(contentsOf: library.fileURL(for: record)),
                      var rect = Optional(NSRect(origin: .zero, size: image.size)),
                      let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }
                let output = batchFramed ? ImagePolish.frame(cg) : cg
                guard let data = Exporter.data(output, format: batchFormat) else { return }
                let safeName = record.title.replacingOccurrences(of: "/", with: "-")
                let destination = folder.appendingPathComponent("\(safeName)-\(record.id.suffix(4)).\(batchFormat.ext)")
                if (try? data.write(to: destination, options: .atomic)) != nil { saved += 1 }
            }
        }
        showBatchSheet = false
        Toast.show("Exported \(saved) image\(saved == 1 ? "" : "s")", symbol: "checkmark.circle.fill")
        NSWorkspace.shared.open(folder)
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
        .task { thumb = await ThumbnailCache.shared.thumbnail(for: library.fileURL(for: record)) }
        .onDisappear { thumb = nil }
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
struct GalleryCard: View {
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
                    // Double-click opens the editor (images) or player (videos); the Annotate
                    // button and ⋯ › Open do the same for keyboard and VoiceOver users.
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture(count: 2) { open() }
                    .accessibilityAction(named: record.kind == .video ? "Play" : "Annotate") { open() }
                    .help(record.kind == .video ? "Double-click to play" : "Double-click to annotate")

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

                if record.kind == .video, library.hasNotes(record) {
                    Button { app.openMeetingNotes(for: record) } label: {
                        Label("Notes", systemImage: "person.2.wave.2.fill")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.5), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(8)
                }
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
                    iconButton("pencil.and.outline", "Annotate again") { app.annotateAgain(record) }
                    iconButton("doc.on.doc", "Copy image") { copyImage() }
                }
                iconButton("square.and.arrow.up", "Share") {
                    SystemShare.file(library.fileURL(for: record))
                }
                iconButton("trash", "Move to Trash") { library.moveToTrash(record) }
                Menu {
                    Button("Open") { open() }
                    if record.kind == .image {
                        Button("Open in Preview") { NSWorkspace.shared.open(library.fileURL(for: record)) }
                    }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([library.fileURL(for: record)]) }
                    Button("Share…", systemImage: "square.and.arrow.up") { SystemShare.file(library.fileURL(for: record)) }
                    if record.kind == .image {
                        Button("Annotate Again", systemImage: "pencil.and.outline") { app.annotateAgain(record) }
                        Button("Copy Image") { copyImage() }
                        Button("Pin to Screen") { PinBoard.pin(url: library.fileURL(for: record)) }
                    }
                    if record.kind == .video {
                        if library.hasNotes(record) {
                            Button("Open Meeting Notes") { app.openMeetingNotes(for: record) }
                            Button("Regenerate Notes") {
                                app.generateNotesForExisting(url: library.fileURL(for: record),
                                                             title: record.title, date: record.createdAt, recordID: record.id)
                            }
                        } else {
                            Button("Meeting Notes") {
                                app.generateNotesForExisting(url: library.fileURL(for: record),
                                                             title: record.title, date: record.createdAt, recordID: record.id)
                            }
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
        .task(id: record.fileName) {
            thumb = await ThumbnailCache.shared.thumbnail(for: library.fileURL(for: record),
                                                          isVideo: record.kind != .image)
        }
        .onDisappear { thumb = nil }   // let the capped cache own off-screen previews
    }

    private func iconButton(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(width: 24, height: 22)
                .background(Theme.chipBG, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain).help(help)
    }

    /// Images open in Snappilot's editor (issue #1); videos in the player.
    private func open() {
        if record.kind == .video {
            VideoPreviewWindowController.present(url: library.fileURL(for: record), title: record.title)
        } else {
            app.annotateAgain(record)
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
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Theme.chipBG, in: RoundedRectangle(cornerRadius: 5))
    }
}

/// A collection's cover tile, loaded as a cached thumbnail instead of decoding in `body`.
private struct CollectionCover: View {
    let url: URL
    let isVideo: Bool
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(height: 120).clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: "photo").font(.system(size: 28)).foregroundStyle(.tertiary)
            }
        }
        .task(id: url) { image = await ThumbnailCache.shared.thumbnail(for: url, isVideo: isVideo) }
        .onDisappear { image = nil }
    }
}
