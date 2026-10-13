import SwiftUI
import SnapCore

/// Saved user styles, persisted across launches.
@MainActor
final class SavedStyleStore: ObservableObject {
    static let shared = SavedStyleStore()
    private static let key = "pref.savedStyles"

    @Published private(set) var styles: SavedStyles

    private init() {
        let data: Data? = Preference.value(Self.key, default: nil)
        styles = data.flatMap { try? JSONDecoder().decode(SavedStyles.self, from: $0) } ?? SavedStyles()
    }

    func add(_ style: AnnotationStyle, for tool: Tool) { styles.add(style, for: tool); persist() }
    func remove(_ style: AnnotationStyle, for tool: Tool) { styles.remove(style, for: tool); persist() }

    private func persist() {
        if let data = try? JSONEncoder().encode(styles) { Preference.set(data, for: Self.key) }
    }
}

/// "My Styles" in the properties panel: save the current look with ＋, reuse it in one click,
/// and push the selected annotation's style onto every annotation of the same kind.
struct MyStylesSection: View {
    @ObservedObject var model: EditorModel
    let tool: Tool
    let selected: Annotation?
    @ObservedObject private var store = SavedStyleStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MY STYLES").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Spacer()
                Button { store.add(model.currentStyle, for: tool) } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("Save the current style")
            }
            let saved = store.styles.styles(for: tool)
            if saved.isEmpty {
                Text("Tweak a style, then press ＋ to keep it.").font(.caption2).foregroundStyle(.tertiary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Array(saved.enumerated()), id: \.offset) { _, style in
                        Button { model.applyStyle(style) } label: {
                            QuickStylePreview(style: QuickStyle(style), tool: tool)
                                .frame(height: 40).frame(maxWidth: .infinity)
                                .background(style == model.currentStyle ? Color.accentColor.opacity(0.22)
                                            : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(style == model.currentStyle ? Color.accentColor : Color.primary.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Saved style \(style.colorHex)")
                        .contextMenu { Button("Remove Style", role: .destructive) { store.remove(style, for: tool) } }
                    }
                }
            }
            if let selected, model.count(of: selected.tool) > 1 {
                Button { model.applyCurrentStyleToAll(of: selected.tool) } label: {
                    Label("Apply to all \(model.count(of: selected.tool))", systemImage: "square.stack.3d.down.right")
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help("Give every annotation of this kind the same style")
            }
        }
    }
}

extension QuickStyle {
    init(_ style: AnnotationStyle) {
        self.init(color: style.colorHex, lineStyle: style.lineStyle, filled: style.filled,
                  startHead: style.startHead, endHead: style.endHead, stepStyle: style.stepStyle,
                  thickness: style.thickness)
    }
}
