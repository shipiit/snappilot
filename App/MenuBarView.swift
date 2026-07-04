import SwiftUI
import SnapCore

private func M(_ hex: String) -> Color { Color(nsColor: nsColor(fromHex: hex)) }

/// The menu-bar popover: capture actions + recording + recent captures.
struct MenuBarView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var hotkeys = HotkeyStore.shared
    @ObservedObject private var library = AppState.shared.library
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""

    private var results: [CaptureRecord] {
        query.isEmpty ? Array(library.records.prefix(4)) : library.search(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            captureGrid
            recordRow
            optionsRow
            divider
            recentSection
            divider
            footer
        }
        .padding(16)
        .frame(width: 340)
        .background(Theme.appBG)
    }

    private var divider: some View { Rectangle().fill(Theme.stroke).frame(height: 1) }

    // MARK: Header
    private var header: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [M("#5661F6"), M("#C850C0")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 36, height: 36)
                .overlay(Image(systemName: "camera.viewfinder").foregroundStyle(.white).font(.system(size: 17, weight: .semibold)))
            VStack(alignment: .leading, spacing: 1) {
                Text("Snappilot").font(.system(size: 15, weight: .bold))
                Text("Capture · Annotate · Record · OCR").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: Capture grid
    private var captureGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            actionCard("Region", "crop", hotkeys.display(.captureRegion), [M("#3B82F6"), M("#2563EB")]) { app.captureRegion() }
            actionCard("Window", "macwindow", hotkeys.display(.captureWindow), [M("#22B8CF"), M("#0E8FA8")]) { app.captureWindow() }
            actionCard("Full Screen", "display", hotkeys.display(.captureFull), [M("#8B5CF6"), M("#6D28D9")]) { app.captureFullScreen() }
            actionCard("Grab Text", "text.viewfinder", hotkeys.display(.grabText), [M("#22C55E"), M("#16A34A")]) { app.grabText() }
        }
    }

    private func actionCard(_ title: String, _ icon: String, _ shortcut: String,
                            _ colors: [Color], _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).frame(height: 22)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Text(shortcut).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.white.opacity(0.2), in: Capsule())
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: Record
    @ViewBuilder private var recordRow: some View {
        if app.isRecording {
            Button { app.stopRecording() } label: {
                Label("Stop recording", systemImage: "stop.circle.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(M("#EF4444"), in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
        } else {
            HStack(spacing: 8) {
                recordCard("Record Region", "record.circle", hotkeys.display(.recordRegion), [M("#F97316"), M("#EF4444")]) { app.recordRegion() }
                recordCard("Record Screen", "rectangle.badge.record", hotkeys.display(.recordScreen), [M("#EC4899"), M("#DB2777")]) { app.recordScreen() }
            }
        }
    }

    private func recordCard(_ title: String, _ icon: String, _ shortcut: String,
                            _ colors: [Color], _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    Text(shortcut).font(.system(size: 8.5, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: Options
    private var optionsRow: some View {
        HStack(spacing: 8) {
            optionChip("Audio", "speaker.wave.2.fill", isOn: $app.recordSystemAudio)
            optionChip("Mic", "mic.fill", isOn: $app.recordMic)
            optionChip("Camera", "web.camera.fill", isOn: $app.recordCamera)
        }
    }

    private func optionChip(_ title: String, _ icon: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isOn.wrappedValue ? .white : .secondary)
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(isOn.wrappedValue ? M("#2563EB") : Theme.cardBG, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.stroke, lineWidth: isOn.wrappedValue ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Recent
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { app.openLibraryFolder() } label: {
                    Label("Folder", systemImage: "folder").font(.system(size: 11))
                }.buttonStyle(.borderless).foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 11))
                TextField("Search captures & text…", text: $query).textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.stroke, lineWidth: 1))

            if results.isEmpty {
                Text(query.isEmpty ? "No captures yet." : "No matches.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 2)
            } else {
                VStack(spacing: 3) {
                    ForEach(results) { rec in recentRow(rec) }
                }
            }
        }
    }

    private func recentRow(_ rec: CaptureRecord) -> some View {
        Button {
            let url = library.fileURL(for: rec)
            if rec.kind == .video { VideoPreviewWindowController.present(url: url, title: rec.title) }
            else { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: rec.kind == .video ? "video.fill" : "photo.fill")
                    .foregroundStyle(.secondary).frame(width: 16).font(.system(size: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text(rec.title).font(.system(size: 12)).lineLimit(1)
                    Text("\(rec.width)×\(rec.height) · \(rec.format)").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.vertical, 5).padding(.horizontal, 7)
            .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer
    private var footer: some View {
        HStack(spacing: 16) {
            footerButton("Settings", "gearshape") { openSettings() }
            footerButton("Guide", "sparkles") { WelcomeWindowController.present(app: app) }
            Spacer()
            footerButton("Quit", "power") { NSApp.terminate(nil) }
        }
    }

    private func footerButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 12)).foregroundStyle(.secondary)
        }.buttonStyle(.plain)
    }
}
