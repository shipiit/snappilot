import SwiftUI

/// A reusable Markdown text editor with a formatting toolbar — shared by the Create-task
/// modal, the task detail description, subtask descriptions, and the comment box, so every
/// place you type behaves the same.
struct MarkdownEditor: View {
    @Binding var text: String
    var placeholder = "Write in Markdown…"
    var minHeight: CGFloat = 130

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder).foregroundStyle(.tertiary).padding(10).allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.body).frame(minHeight: minHeight).padding(6)
                    .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.panelBG, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke))
    }

    private var toolbar: some View {
        HStack(spacing: 1) {
            wrap("bold", "**", "**")
            wrap("italic", "*", "*")
            wrap("strikethrough", "~~", "~~")
            Divider().frame(height: 16)
            insert("textformat.size", "\n# ")
            insert("list.bullet", "\n- ")
            insert("list.number", "\n1. ")
            insert("checklist", "\n- [ ] ")
            insert("text.quote", "\n> ")
            wrap("chevron.left.forwardslash.chevron.right", "`", "`")
            insert("link", "[text](url)")
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
    }

    private func wrap(_ icon: String, _ pre: String, _ post: String) -> some View {
        Button { text += "\(pre)text\(post)" } label: { Image(systemName: icon).font(.system(size: 12)) }
            .buttonStyle(.borderless).frame(width: 24, height: 22)
    }
    private func insert(_ icon: String, _ snippet: String) -> some View {
        Button { text += snippet } label: { Image(systemName: icon).font(.system(size: 12)) }
            .buttonStyle(.borderless).frame(width: 24, height: 22)
    }
}
