import SwiftUI

/// The three summary cards under the header.
struct DashboardStatCards: View {
    let captureCount: Int
    let openLibrary: () -> Void
    let export: () -> Void
    @State private var showPrivacy = false

    var body: some View {
        HStack(spacing: 14) {
            card(icon: "folder.fill", tint: "#3B82F6", title: "Local library",
                 detail: Text("\(captureCount.formatted())").font(.system(size: 18, weight: .bold))
                    + Text(captureCount == 1 ? "  capture" : "  captures").font(.system(size: 13)).foregroundColor(.secondary),
                 action: openLibrary)
            card(icon: "square.and.arrow.up", tint: "#8B5CF6", title: "Ready to share",
                 detail: Text("PNG · JPEG · MP4 · PDF · GIF").font(.system(size: 12)).foregroundColor(.secondary),
                 action: export)
            card(icon: "checkmark.shield.fill", tint: "#10B981", title: "Private by design",
                 detail: Text("OCR stays on this Mac").font(.system(size: 12)).foregroundColor(.secondary)) {
                showPrivacy.toggle()
            }
            .popover(isPresented: $showPrivacy, arrowEdge: .bottom) {
                Text("Captures, text recognition and meeting transcripts are processed on this Mac. Nothing is uploaded.")
                    .font(.callout).padding(14).frame(width: 280)
            }
        }
    }

    private func card(icon: String, tint: String, title: String, detail: Text,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(hexColor(tint))
                    .frame(width: 44, height: 44)
                    .background(hexColor(tint).opacity(0.16), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    detail.lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
