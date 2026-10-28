import AppKit
import SwiftUI

/// Other free apps from the same team, with direct download links.
struct MoreFromShipiit: View {
    private struct App: Identifiable {
        let name: String, tagline: String, platform: String, icon: String, colors: [String]
        let download: URL, website: URL
        var id: String { name }
    }

    private let apps: [App] = [
        App(name: "Mac Sweep",
            tagline: "Clean, monitor, protect and understand your Mac — developer tools, AI usage and system insights.",
            platform: "macOS 15+ · Apple Silicon", icon: "sparkles", colors: ["#0EA5E9", "#6366F1"],
            download: URL(string: "https://github.com/shipiit/mac-sweep/releases/latest")!,
            website: URL(string: "https://shipiit.github.io/mac-sweep-website/")!),
        App(name: "KeyVault",
            tagline: "Local-only, zero-knowledge password manager for Chrome. AES-256 vault and built-in 2FA codes.",
            platform: "Chrome extension · No account", icon: "key.fill", colors: ["#10B981", "#0F766E"],
            download: URL(string: "https://github.com/shipiit/keyvault/releases/latest")!,
            website: URL(string: "https://shipiit.github.io/keyvault/")!),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("More from Shipiit").font(.system(size: 20, weight: .semibold))
                Text("Free, open-source and private — like Snappilot.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) { ForEach(apps) { card($0) } }
        }
    }

    private func card(_ app: App) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: app.icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(LinearGradient(colors: app.colors.map(hexColor), startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(app.name).font(.system(size: 15, weight: .semibold))
                    Text(app.platform).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(app.tagline).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button { NSWorkspace.shared.open(app.download) } label: { Label("Download", systemImage: "arrow.down.circle.fill") }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Button("Learn more") { NSWorkspace.shared.open(app.website) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 1))
    }
}
