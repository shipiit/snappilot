import SwiftUI

/// The home dashboard: header, summary, capture tools, recording options, recent captures
/// and other apps. Composition only — each block is its own view.
struct DashboardView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var library: LibraryStore
    let openSection: (HomeSection) -> Void
    let openSettings: () -> Void
    let export: () -> Void
    let exportPDF: () -> Void
    let newCollection: () -> Void

    @State private var query = ""
    @AppStorage("dashboard.bannerDismissed") private var bannerDismissed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DashboardHeader(query: $query, openSettings: openSettings)
                if query.isEmpty {
                    DashboardStatCards(captureCount: library.records.count,
                                       openLibrary: { openSection(.library) }, export: export)
                    if !bannerDismissed {
                        DashboardBanner { withAnimation(.easeInOut(duration: 0.2)) { bannerDismissed = true } }
                    }
                    QuickCaptureGrid(openShortcuts: openSettings)
                    RecordingOptionsBar()
                    if !app.capturePresets.isEmpty { PresetStrip() }
                }
                RecentCapturesSection(library: library, query: query, limit: query.isEmpty ? 12 : 48,
                                      export: export, exportPDF: exportPDF, newCollection: newCollection,
                                      showAll: { openSection(.library) })
                if query.isEmpty { MoreFromShipiit() }
            }
            .padding(28)
            .frame(maxWidth: 1600)
            .frame(maxWidth: .infinity)
        }
    }
}
