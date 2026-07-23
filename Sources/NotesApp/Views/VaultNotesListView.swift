import NotesCore
import SwiftUI

struct VaultNotesListView: View {
    @EnvironmentObject private var store: VaultStore
    let onRename: (NotePath) -> Void
    let onTrash: (NotePath) -> Void

    private var selection: Binding<NotePath?> {
        Binding(get: { store.selectedNotePath }, set: { store.selectNote($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.selectedFolder.isRoot ? store.text("allNotes") : store.selectedFolder.name)
                        .font(.title2.bold())
                    Text(store.format("markdownFilesCount", store.visibleNotes.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)

            Divider()

            if store.visibleNotes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text(store.text("noMarkdownNotes"))
                        .font(.headline)
                    Button(store.text("createNote")) { store.createNote() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: selection) {
                    ForEach(store.visibleNotes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            Text(note.path.value)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(note.modifiedAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            if !store.searchText.isEmpty,
                               let result = store.searchResults.first(where: { $0.path == note.path }) {
                                SearchSnippetText(snippet: result.snippet)
                                    .font(.caption)
                                    .lineLimit(3)
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(note.path)
                        .contextMenu {
                            Button(store.text("rename")) { onRename(note.path) }
                            Button(store.text("duplicate")) { store.duplicate(note.path) }
                            Button(store.text("revealFinder")) { store.reveal(note.path) }
                            Divider()
                            Button(store.text("moveTrash"), role: .destructive) { onTrash(note.path) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $store.searchText, prompt: store.text("searchFilesPaths"))
        .navigationTitle(store.selectedFolder.isRoot ? store.text("allNotes") : store.selectedFolder.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { store.createNote() } label: {
                    Label(store.text("newNote"), systemImage: "plus")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if store.indexStatus.phase == .indexing || store.indexStatus.phase == .failed {
                HStack(spacing: 8) {
                    if store.indexStatus.phase == .indexing {
                        ProgressView(value: Double(store.indexStatus.completed), total: Double(max(1, store.indexStatus.total)))
                            .frame(width: 80)
                        Button(store.text("cancel")) { store.cancelIndexing() }
                            .buttonStyle(.borderless)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Text(store.indexStatus.message).lineLimit(1)
                    Spacer()
                }
                .font(.caption)
                .padding(8)
                .background(.bar)
            }
        }
    }
}

private struct SearchSnippetText: View {
    let snippet: String

    var body: some View {
        Text(attributedSnippet)
            .foregroundStyle(.secondary)
    }

    private var attributedSnippet: AttributedString {
        var result = AttributedString()
        let components = snippet.components(separatedBy: "<mark>")
        for (index, component) in components.enumerated() {
            if index == 0 {
                result.append(AttributedString(component))
                continue
            }
            let markedParts = component.components(separatedBy: "</mark>")
            var highlighted = AttributedString(markedParts[0])
            highlighted.backgroundColor = .yellow.opacity(0.45)
            highlighted.foregroundColor = .primary
            result.append(highlighted)
            if markedParts.count > 1 { result.append(AttributedString(markedParts.dropFirst().joined(separator: "</mark>"))) }
        }
        return result
    }
}
