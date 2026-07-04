import SwiftUI
import CoreGraphics

/// One page of the walkthrough.
private struct Page: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let subtitle: String
    let bullets: [(String, String)]   // (sf symbol, text)
    let gradient: [Color]
}

/// A long, friendly first-run walkthrough: welcome → capture → annotate → OCR →
/// library → shortcuts → permission → get started.
struct WelcomeView: View {
    @EnvironmentObject var app: AppState
    var onFinish: () -> Void

    @State private var index = 0
    @State private var screenGranted = CGPreflightScreenCaptureAccess()

    private let pages: [Page] = [
        Page(symbol: "camera.viewfinder",
             title: "Welcome to Snappilot",
             subtitle: "The free, private, open-source screen-capture studio for your Mac.",
             bullets: [
                ("bolt.fill", "Capture, annotate, and pull text out of anything on screen"),
                ("lock.fill", "100% on-device — nothing ever leaves your Mac"),
                ("heart.fill", "Open source and yours to shape"),
             ],
             gradient: [.pink, .orange]),
        Page(symbol: "crop",
             title: "Capture exactly what you want",
             subtitle: "Grab a region, a single window, or the whole screen.",
             bullets: [
                ("crop", "Drag a crosshair to select any region, with live dimensions"),
                ("macwindow", "Hover to highlight and click a single window"),
                ("rectangle.inset.filled", "Or capture the full screen in one shot"),
             ],
             gradient: [.blue, .indigo]),
        Page(symbol: "pencil.and.outline",
             title: "Annotate like a pro",
             subtitle: "A full editor opens with every capture.",
             bullets: [
                ("arrow.up.right", "Arrows, lines, rectangles, ellipses & freehand pen"),
                ("1.circle.fill", "Auto-numbered step badges for tutorials"),
                ("eye.slash", "Blur / redact sensitive info · highlight · text callouts"),
                ("arrow.uturn.backward", "Non-destructive — move, edit, undo anything"),
             ],
             gradient: [.purple, .pink]),
        Page(symbol: "text.viewfinder",
             title: "Grab Text with OCR",
             subtitle: "Turn any picture of text into text you can paste.",
             bullets: [
                ("doc.on.clipboard.fill", "Select a region → text is copied instantly"),
                ("cpu", "Powered by Apple Vision, fully offline"),
                ("magnifyingglass", "Your captures become searchable by the words inside them"),
             ],
             gradient: [.teal, .green]),
        Page(symbol: "photo.stack",
             title: "Your captures, organized",
             subtitle: "Everything auto-saves to a tidy local library.",
             bullets: [
                ("folder.fill", "Saved to ~/Pictures/Snappilot, grouped by month"),
                ("magnifyingglass", "Search past captures — even by their OCR text"),
                ("clock.arrow.circlepath", "Recent captures live in the menu bar"),
             ],
             gradient: [.orange, .yellow]),
        Page(symbol: "keyboard",
             title: "Fast global shortcuts",
             subtitle: "Fire a capture from any app, anytime.",
             bullets: [
                ("camera", "⌃⇧1 Region · ⌃⇧2 Window · ⌃⇧3 Full screen"),
                ("text.viewfinder", "⌃⇧4  Grab text (OCR)"),
                ("record.circle", "⌃⇧5 Record region · ⌃⇧6 Record screen"),
                ("stop.circle", "⌃⇧.  Stop recording"),
             ],
             gradient: [.indigo, .blue]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.offset) { i, page in
                    pageView(page).tag(i)
                }
                permissionPage.tag(pages.count)
            }
            .tabViewStyle(.automatic)

            footer
        }
        .frame(width: 640, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Pages
    private func pageView(_ page: Page) -> some View {
        VStack(spacing: 22) {
            hero(page.symbol, page.gradient)
            VStack(spacing: 8) {
                Text(page.title).font(.system(size: 28, weight: .bold))
                Text(page.subtitle).font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(page.bullets, id: \.1) { icon, text in
                    HStack(spacing: 14) {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(page.gradient.first ?? .accentColor)
                            .frame(width: 26)
                        Text(text).font(.body)
                        Spacer()
                    }
                }
            }
            .padding(24)
            .frame(width: 460)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            Spacer()
        }
        .padding(.top, 44)
    }

    private var permissionPage: some View {
        VStack(spacing: 22) {
            hero(screenGranted ? "checkmark.shield.fill" : "shield.lefthalf.filled",
                 screenGranted ? [.green, .mint] : [.orange, .red])
            VStack(spacing: 8) {
                Text(screenGranted ? "You're all set!" : "One quick permission")
                    .font(.system(size: 28, weight: .bold))
                Text(screenGranted
                     ? "Screen Recording is enabled. Take your first capture below."
                     : "macOS needs your OK to let Snappilot see the screen. Nothing is uploaded — it stays on your Mac.")
                    .font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }

            if !screenGranted {
                Button {
                    _ = CGRequestScreenCaptureAccess()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        screenGranted = CGPreflightScreenCaptureAccess()
                    }
                } label: {
                    Label("Enable Screen Recording", systemImage: "lock.open.fill")
                        .frame(maxWidth: 300).padding(.vertical, 6)
                }
                .controlSize(.large).buttonStyle(.borderedProminent)
                Text("If macOS opens System Settings, toggle Snappilot on, then return here.")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                Button {
                    finish(); app.captureRegion()
                } label: {
                    Label("Take your first capture", systemImage: "camera.viewfinder")
                        .frame(maxWidth: 300).padding(.vertical, 6)
                }
                .controlSize(.large).buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding(.top, 44)
        .onAppear { screenGranted = CGPreflightScreenCaptureAccess() }
    }

    private func hero(_ symbol: String, _ colors: [Color]) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 104, height: 104)
                .shadow(color: (colors.first ?? .accentColor).opacity(0.4), radius: 16, y: 8)
            Image(systemName: symbol).font(.system(size: 46, weight: .semibold)).foregroundStyle(.white)
        }
    }

    // MARK: Footer
    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(0...pages.count, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: i == index ? 20 : 7, height: 7)
                        .animation(.spring(duration: 0.3), value: index)
                }
            }
            HStack {
                Button("Skip") { finish() }.buttonStyle(.borderless).foregroundStyle(.secondary)
                Spacer()
                if index > 0 {
                    Button { withAnimation { index -= 1 } } label: { Label("Back", systemImage: "chevron.left") }
                        .buttonStyle(.borderless)
                }
                if index < pages.count {
                    Button { withAnimation { index += 1 } } label: {
                        Label("Next", systemImage: "chevron.right").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button { finish() } label: { Text("Get Started").frame(minWidth: 90) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 16)
        .background(.bar)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
        onFinish()
    }
}
