import SwiftUI

/// The dismissible welcome banner. Dismissal is remembered.
struct DashboardBanner: View {
    let dismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    (Text("Capture ").foregroundColor(.white)
                        + Text("Anything, Work Smarter").foregroundColor(hexColor("#C7D2FE")))
                        .font(.system(size: 26, weight: .bold))
                    Text("Screenshots, videos, text (OCR) — all in one place.")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 12)
                illustration
            }
            .padding(.horizontal, 30).padding(.vertical, 22)

            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain).padding(12).help("Hide banner").accessibilityLabel("Hide banner")
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [hexColor("#4338CA"), hexColor("#6D28D9"), hexColor("#7C3AED")],
                           startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.14), lineWidth: 1))
    }

    /// Decorative tiles: text recognition, an image and a video.
    private var illustration: some View {
        HStack(alignment: .bottom, spacing: 14) {
            tile("text.viewfinder", size: 52, colors: ["#60A5FA", "#3B82F6"]).offset(y: -14)
            tile("photo.fill", size: 60, colors: ["#38BDF8", "#6366F1"])
            tile("play.fill", size: 66, colors: ["#F472B6", "#DB2777"]).offset(y: 6)
        }
        .padding(.trailing, 30)
        .accessibilityHidden(true)
    }

    private func tile(_ symbol: String, size: CGFloat, colors: [String]) -> some View {
        Image(systemName: symbol).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: colors.map(hexColor), startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: size * 0.24))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}
