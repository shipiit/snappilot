import AppKit
import SwiftUI
import SnapCore

/// Greeting, library search (⌘K), light/dark switch and the account initial.
struct DashboardHeader: View {
    @EnvironmentObject var app: AppState
    @Binding var query: String
    let openSettings: () -> Void
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var firstName: String? { LibraryQuery.firstName(NSFullUserName()) }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting).font(.system(size: 28, weight: .bold))
                Text("Capture, annotate and organize your work with ease.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            search
            Button { toggleAppearance() } label: {
                Image(systemName: colorScheme == .dark ? "sun.max" : "moon")
                    .font(.system(size: 15)).frame(width: 36, height: 36)
                    .background(Theme.cardBG, in: Circle())
                    .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(colorScheme == .dark ? "Switch to light appearance" : "Switch to dark appearance")
            Button(action: openSettings) {
                Text(String(firstName?.prefix(1) ?? "S").uppercased())
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(LinearGradient(colors: [hexColor("#3B82F6"), hexColor("#8B5CF6")],
                                               startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            }
            .buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
        }
    }

    private var greeting: String {
        let hello = LibraryQuery.greeting(hour: Calendar.current.component(.hour, from: Date()))
        return firstName.map { "\(hello), \($0) 👋" } ?? "\(hello) 👋"
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search captures, text, collections…", text: $query)
                .textFieldStyle(.plain).focused($searchFocused)
                .onAppear { DispatchQueue.main.async { searchFocused = false } }   // don't grab keys at launch
                .onExitCommand { query = ""; searchFocused = false }
            if query.isEmpty {
                Text("⌘K").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.chipBG, in: RoundedRectangle(cornerRadius: 5))
            } else {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(width: 400)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(searchFocused ? Color.accentColor : Theme.stroke, lineWidth: searchFocused ? 2 : 1))
        .background {
            Button("Search") { searchFocused = true }.keyboardShortcut("k").hidden()
        }
    }

    private func toggleAppearance() {
        app.appearance = colorScheme == .dark ? .light : .dark
    }
}
