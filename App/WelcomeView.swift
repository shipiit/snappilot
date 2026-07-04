import SwiftUI
import CoreGraphics
import AVFoundation

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
             subtitle: "Region, window, or full screen — with a pixel-perfect magnifier.",
             bullets: [
                ("crop", "Click a card or press ⌃⇧1, then drag a crosshair — a magnifier loupe shows the exact pixels"),
                ("macwindow", "⌃⇧2 hovers & highlights a single app window — just click it"),
                ("rectangle.inset.filled", "⌃⇧3 grabs the whole screen (or press F inside the overlay)"),
                ("timer", "Set a 3s / 5s Delay on the dashboard for timed shots · Esc cancels · M toggles the magnifier"),
             ],
             gradient: [.blue, .indigo]),
        Page(symbol: "pencil.and.outline",
             title: "Annotate like a pro",
             subtitle: "A Snagit-style editor opens with every capture.",
             bullets: [
                ("arrow.up.right", "Arrows, lines, shapes, text, callouts, pen, stamps — top toolbar or press 1–9"),
                ("paintpalette.fill", "Quick Styles: 10+ one-click presets per tool; tune color, thickness, opacity & arrow ends"),
                ("1.circle.fill", "Auto-numbered step badges (1·2·3 / A·B·C / a·b·c) and emoji stamps"),
                ("eye.slash.fill", "Blur, crop, highlight — or hit Redact to auto-blur detected emails & card numbers"),
             ],
             gradient: [.purple, .pink]),
        Page(symbol: "record.circle.fill",
             title: "Record your screen",
             subtitle: "Region or full screen → a compact HEVC video.",
             bullets: [
                ("slider.horizontal.3", "Toggle system audio, mic, camera overlay, cursor & countdown before you start"),
                ("viewfinder", "A Ready-to-Record panel + 3·2·1 countdown; a yellow frame shows what's being captured"),
                ("wand.and.stars", "Choose Small / Balanced / High quality to trade file size vs. sharpness"),
                ("photo.stack", "Playback opens inside Snappilot — export, copy, or turn it into a GIF"),
             ],
             gradient: [.red, .orange]),
        Page(symbol: "text.viewfinder",
             title: "Grab Text with OCR",
             subtitle: "Turn any picture of text into text you can paste.",
             bullets: [
                ("doc.on.clipboard.fill", "Press ⌃⇧4, select a region → the text is copied to your clipboard instantly"),
                ("cpu", "Apple Vision on-device — fully private, works offline"),
                ("magnifyingglass", "Your captures become searchable by the words inside them"),
             ],
             gradient: [.teal, .green]),
        Page(symbol: "photo.stack",
             title: "Your captures, organized",
             subtitle: "Everything auto-saves to a tidy local library.",
             bullets: [
                ("folder.fill", "Saved to ~/Pictures/Snappilot by month — browse Dashboard, Library, Favorites & Collections"),
                ("magnifyingglass", "Search past captures, even by their OCR'd text"),
                ("star.fill", "★ favorite, copy, or move to Trash right from each card"),
                ("circle.lefthalf.filled", "Full light & dark theme — automatically follows your system"),
             ],
             gradient: [.orange, .yellow]),
        Page(symbol: "keyboard",
             title: "Fast global shortcuts",
             subtitle: "Fire a capture from any app, anytime — and make them yours.",
             bullets: [
                ("camera", "⌃⇧1 Region · ⌃⇧2 Window · ⌃⇧3 Full screen · ⌃⇧4 Grab Text"),
                ("record.circle", "⌃⇧5 Record region · ⌃⇧6 Record screen · ⌃⇧. Stop"),
                ("menubar.arrow.up.rectangle", "The menu-bar icon has every action + your recent captures"),
                ("slider.horizontal.3", "Customize every shortcut in Settings → Shortcuts"),
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
        .frame(width: 660, height: 600)
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
                     ? "Screen Recording is enabled. Grant Camera & Microphone too, or start capturing."
                     : "Grant these once so you never get interrupted later. Everything stays on your Mac — nothing is uploaded.")
                    .font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }

            if !screenGranted {
                Button {
                    // Ask for all three up front: Screen Recording, Camera, Microphone.
                    _ = CGRequestScreenCaptureAccess()
                    Task {
                        _ = await AVCaptureDevice.requestAccess(for: .video)
                        _ = await AVCaptureDevice.requestAccess(for: .audio)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        screenGranted = CGPreflightScreenCaptureAccess()
                    }
                } label: {
                    Label("Enable all permissions", systemImage: "lock.open.fill")
                        .frame(maxWidth: 300).padding(.vertical, 6)
                }
                .controlSize(.large).buttonStyle(.borderedProminent)
                Text("Grants Screen Recording, Camera & Microphone. If Settings opens, toggle Snappilot on and return.")
                    .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center).padding(.horizontal, 30)
            } else {
                Button {
                    Task {
                        _ = await AVCaptureDevice.requestAccess(for: .video)
                        _ = await AVCaptureDevice.requestAccess(for: .audio)
                    }
                } label: {
                    Label("Also allow Camera & Microphone", systemImage: "camera.fill")
                        .frame(maxWidth: 300).padding(.vertical, 6)
                }
                .controlSize(.large).buttonStyle(.bordered)
            }
            if screenGranted {
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
                .fill((colors.first ?? Color.accentColor))
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
