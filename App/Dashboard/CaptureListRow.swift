import SwiftUI
import SnapCore

/// A compact row for the list layout of Recent Captures.
struct CaptureListRow: View {
    @EnvironmentObject var app: AppState
    let record: CaptureRecord
    @ObservedObject var library: LibraryStore
    @State private var thumb: NSImage?

    var body: some View {
        HStack(spacing: 14) {
            Button(action: open) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 7).fill(Theme.panelBG)
                        .frame(width: 84, height: 52)
                        .overlay {
                            if let thumb { Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill) }
                            else { Image(systemName: record.kind == .video ? "video.fill" : "photo").foregroundStyle(.tertiary) }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(record.format).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.chipBG, in: Capsule())
                    Text("\(record.width) × \(record.height)").font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary).frame(width: 96, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(record.kind == .video ? "Play" : "Open in the editor")
            Button { library.toggleFavorite(id: record.id) } label: {
                Image(systemName: record.favorite ? "star.fill" : "star")
                    .foregroundStyle(record.favorite ? Color.yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(record.favorite ? "Remove from Favorites" : "Add to Favorites")
            Button { SystemShare.file(library.fileURL(for: record)) } label: { Image(systemName: "square.and.arrow.up") }
                .buttonStyle(.borderless).help("Share")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.stroke, lineWidth: 1))
        .task(id: record.fileName) {
            thumb = await ThumbnailCache.shared.thumbnail(for: library.fileURL(for: record), isVideo: record.kind != .image)
        }
        .onDisappear { thumb = nil }
    }

    private func open() {
        if record.kind == .video {
            VideoPreviewWindowController.present(url: library.fileURL(for: record), title: record.title)
        } else {
            app.annotateAgain(record)
        }
    }
}
