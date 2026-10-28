import SwiftUI
import SnapCore

/// Recent captures with filters, sort, grid/list layout, export and collections.
struct RecentCapturesSection: View {
    @ObservedObject var library: LibraryStore
    let query: String
    let limit: Int
    let export: () -> Void
    let exportPDF: () -> Void
    let newCollection: () -> Void
    let showAll: () -> Void

    @AppStorage("dashboard.filter") private var filter: CaptureFilter = .all
    @AppStorage("dashboard.sort") private var sort: CaptureSort = .newest
    @AppStorage("dashboard.listLayout") private var listLayout = false

    var body: some View {
        let matches = LibraryQuery.apply(library.records, filter: filter, sort: sort, query: query,
                                         hasMeetingNotes: library.hasNotes)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(query.isEmpty ? "Recent Captures" : "Results").font(.system(size: 20, weight: .semibold))
                    .padding(.trailing, 8)
                ForEach(CaptureFilter.allCases) { option in
                    Button { filter = option } label: {
                        Text(option.title).font(.system(size: 12, weight: filter == option ? .semibold : .regular))
                            .foregroundStyle(filter == option ? Color.white : Color.primary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(filter == option ? Color.accentColor : Theme.chipBG, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == option ? .isSelected : [])
                }
                Spacer(minLength: 8)
                Picker("Sort", selection: $sort) {
                    ForEach(CaptureSort.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().fixedSize()
                Picker("Layout", selection: $listLayout) {
                    Image(systemName: "square.grid.2x2").tag(false).accessibilityLabel("Grid")
                    Image(systemName: "list.bullet").tag(true).accessibilityLabel("List")
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
                Menu {
                    Button("Export Images…", systemImage: "photo.stack", action: export)
                    Button("Export as PDF…", systemImage: "doc.richtext", action: exportPDF)
                } label: { Label("Export", systemImage: "square.and.arrow.down") }
                    .fixedSize()
                Button(action: newCollection) { Label("New Collection", systemImage: "plus") }.buttonStyle(.borderedProminent)
            }
            if matches.isEmpty {
                emptyState
            } else if listLayout {
                LazyVStack(spacing: 8) {
                    ForEach(matches.prefix(limit)) { CaptureListRow(record: $0, library: library) }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 18)], spacing: 18) {
                    ForEach(matches.prefix(limit)) { GalleryCard(record: $0, library: library) }
                }
            }
            if matches.count > limit {
                Button(action: showAll) { Label("Show all \(matches.count.formatted())", systemImage: "arrow.right") }
                    .buttonStyle(.bordered).frame(maxWidth: .infinity)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: query.isEmpty ? "photo.on.rectangle.angled" : "magnifyingglass")
                .font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(query.isEmpty ? "Nothing here yet" : "No captures match “\(query)”").foregroundStyle(.secondary)
            if filter != .all { Button("Show all captures") { filter = .all }.buttonStyle(.bordered) }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
