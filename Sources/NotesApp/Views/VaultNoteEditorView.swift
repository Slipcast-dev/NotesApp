import NotesCore
import SwiftUI

struct VaultNoteEditorView: View {
    @EnvironmentObject private var store: VaultStore
    @StateObject private var editorController = MarkdownEditorController()
    @StateObject private var editorSession = EditorSession()
    @State private var tableContext: MarkdownTableEditContext?
    let onRename: (NotePath) -> Void
    let onTrash: (NotePath) -> Void

    var body: some View {
        Group {
            if let note = store.currentNote {
                editor(note)
            } else {
                emptyState
            }
        }
        .navigationTitle(store.currentNote?.title ?? "NotesApp")
        .toolbar {
            if let path = store.selectedNotePath {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        _ = store.saveCurrentNote()
                    } label: {
                        Label(store.text("saveMarkdown"), systemImage: "square.and.arrow.down")
                    }
                    .disabled(!store.isModified)

                    Menu {
                        Button(store.text("rename")) { onRename(path) }
                        Button(store.text("duplicate")) { store.duplicate(path) }
                        Button(store.text("revealFinder")) { store.reveal(path) }
                        Divider()
                        Button(store.text("moveTrash"), role: .destructive) { onTrash(path) }
                    } label: {
                        Label(store.text("noteActions"), systemImage: "ellipsis.circle")
                    }
                }
            }

            ToolbarItem(placement: .automatic) {
                Button { PlatformServices.openSettings() } label: {
                    Label(store.text("settings"), systemImage: "gearshape")
                }
            }
        }
    }

    private func editor(_ note: VaultNote) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(note.title) { onRename(note.path) }
                    .buttonStyle(.plain)
                    .font(.system(size: 26, weight: .bold))
                Spacer()
                Picker(store.text("editorMode"), selection: editorModeBinding) {
                    Text(store.text("source")).tag(EditorMode.source)
                    Text(store.text("livePreview")).tag(EditorMode.livePreview)
                    Text(store.text("reading")).tag(EditorMode.reading)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            switch editorSession.mode {
            case .source:
                Divider()
                formattingBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                Divider()

                MarkdownSourceEditor(
                    markdown: $store.draftMarkdown,
                    fontFamily: store.appSettings.fontFamily,
                    fontSize: store.appSettings.fontSize,
                    controller: editorController,
                    syntaxMode: .source,
                    onImportFiles: { store.importAttachments($0) },
                    onImportImage: { store.importClipboardImage($0, fileExtension: $1) }
                )
                .id(note.path)
            case .livePreview:
                Divider()
                visualEditingBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                Divider()
                renderedMarkdown(allowsTableEditing: true)
            case .reading:
                Divider()
                renderedMarkdown(allowsTableEditing: false)
            }

            metadataPanel

            Divider()
            HStack(spacing: 8) {
                Image(systemName: store.isModified ? "circle.fill" : "checkmark.circle")
                    .foregroundStyle(store.isModified ? Color.orange : Color.secondary)
                Text(store.isModified ? store.text("unsavedMarkdown") : store.text("saved"))
                Spacer()
                Text(store.format("wordsCount", wordCount))
                Text(store.format("charactersCount", store.draftMarkdown.count))
                Text(note.path.value)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .onAppear { editorSession.activate(note.path) }
        .onChange(of: note.path) { newPath in editorSession.activate(newPath) }
        .sheet(item: $tableContext) { context in
            MarkdownTableEditorView(
                draft: context.draft,
                language: store.appSettings.language
            ) { draft in
                let replacement = context.replacementMarkdown(with: draft)
                if editorSession.mode == .source {
                    editorController.replaceMarkdown(in: context.range, with: replacement)
                } else {
                    store.draftMarkdown = MarkdownInteractiveEditor().replacingTable(
                        in: store.draftMarkdown,
                        context: context,
                        with: draft
                    )
                }
                editorSession.mode = .livePreview
            }
        }
    }

    private func renderedMarkdown(allowsTableEditing: Bool) -> some View {
        MarkdownReadingView(
            markdown: $store.draftMarkdown,
            language: store.appSettings.language,
            allowsTableEditing: allowsTableEditing,
            onEditTable: { range in
                tableContext = MarkdownInteractiveEditor().table(
                    in: store.draftMarkdown,
                    nearUTF16Location: range.lowerBound
                )
            }
        )
    }

    private var visualEditingBar: some View {
        HStack(spacing: 12) {
            Button {
                changeEditorMode(to: .source)
            } label: {
                Label(store.text("editMarkdown"), systemImage: "pencil")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("e", modifiers: .command)

            Button {
                openTableEditor(existingOnly: false)
            } label: {
                Label(store.text("insertTable"), systemImage: "tablecells.badge.ellipsis")
            }
            .buttonStyle(.borderless)

            Spacer()
            Text(store.text("visualPreviewHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .controlSize(.small)
    }

    private var formattingBar: some View {
        HStack(spacing: 5) {
            Group {
                editorButton("bold", help: store.text("bold")) { editorController.toggleBold() }
                editorButton("italic", help: store.text("italic")) { editorController.toggleItalic() }
                editorButton("strikethrough", help: store.text("strikethrough")) { editorController.toggleStrikethrough() }
                editorButton("highlighter", help: store.text("highlight")) { editorController.toggleHighlight() }
                editorButton("textformat.size.larger", help: store.text("heading")) { editorController.applyHeading() }
            }
            Divider().frame(height: 18)
            Group {
                editorButton("list.bullet", help: store.text("bulletList")) { editorController.insertBullet() }
                editorButton("list.number", help: store.text("numberedList")) { editorController.insertNumberedList() }
                editorButton("checklist", help: store.text("task")) { editorController.insertTask() }
                editorButton("checkmark.square", help: store.text("toggleTask")) { editorController.toggleTaskAtSelection() }
                editorButton("text.quote", help: store.text("blockquote")) { editorController.insertQuote() }
            }
            Divider().frame(height: 18)
            Group {
                editorButton("chevron.left.forwardslash.chevron.right", help: store.text("inlineCode")) { editorController.insertInlineCode() }
                editorButton("curlybraces.square", help: store.text("codeBlock")) { editorController.insertCodeBlock() }
                Menu {
                    Button(store.text("editTable")) { openTableEditor(existingOnly: true) }
                    Button(store.text("insertTable")) { openTableEditor(existingOnly: false) }
                } label: { Image(systemName: "tablecells") }
                .menuStyle(.borderlessButton)
                .help(store.text("table"))
                editorButton("link", help: store.text("markdownLink")) { editorController.insertMarkdownLink() }
                editorButton("link.badge.plus", help: store.text("wikilink")) { editorController.insertWikilink() }
                editorButton("paperclip", help: store.text("attachFiles")) {
                    let urls = PlatformServices.chooseAttachmentFiles(startingAt: store.vaultURL)
                    if let markdown = store.importAttachments(urls) { editorController.insertMarkdown(markdown) }
                }
            }
            Spacer()
            Button { editorController.showFindPanel() } label: {
                Label(store.text("find"), systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderless)
        }
        .controlSize(.small)
    }

    private func editorButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }
            .buttonStyle(.borderless)
            .help(help)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(store.text("selectMarkdownNote"))
                .font(.title2.bold())
            Text(store.text("fileFirstHint"))
                .foregroundStyle(.secondary)
            Button(store.text("createNote")) { store.createNote() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorModeBinding: Binding<EditorMode> {
        Binding(
            get: { editorSession.mode },
            set: { changeEditorMode(to: $0) }
        )
    }

    private func changeEditorMode(to newMode: EditorMode) {
        if let path = store.selectedNotePath, let selection = editorController.selectedRange {
            editorSession.remember(selection: selection, scrollOffset: 0, for: path)
        }
        editorSession.mode = newMode
        if newMode == .source, let path = store.selectedNotePath {
            DispatchQueue.main.async {
                editorController.restoreSelection(editorSession.selection(for: path))
            }
        }
    }

    private var metadataPanel: some View {
        DisclosureGroup {
            HStack(alignment: .top, spacing: 24) {
                metadataColumn(store.text("outline"), kind: .outline, empty: store.text("noHeadings")) {
                    ForEach(store.indexedHeadings, id: \.text) { heading in
                        Text(String(repeating: "  ", count: max(0, heading.level - 1)) + heading.text)
                            .lineLimit(1)
                    }
                }
                metadataColumn(store.text("outgoingLinks"), kind: .outgoing, empty: store.text("noLinks")) {
                    ForEach(Array(store.indexedOutgoingLinks.enumerated()), id: \.offset) { _, link in
                        Button(link.label ?? link.destination) { store.openIndexedLink(link) }
                            .buttonStyle(.link)
                            .lineLimit(1)
                    }
                }
                metadataColumn(store.text("backlinks"), kind: .backlinks, empty: store.text("noBacklinks")) {
                    ForEach(Array(store.indexedBacklinks.enumerated()), id: \.offset) { _, link in
                        Button(link.sourcePath.deletingPathExtension) { store.openBacklink(link) }
                            .buttonStyle(.link)
                            .help(link.context)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label(
                store.format(
                    "outlineLinksSummary",
                    store.indexedHeadings.count,
                    store.indexedOutgoingLinks.count,
                    store.indexedBacklinks.count
                ),
                systemImage: "point.3.connected.trianglepath.dotted"
            )
            .font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private func metadataColumn<Content: View>(
        _ title: String,
        kind: MetadataKind,
        empty: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.bold())
            if (kind == .outline && store.indexedHeadings.isEmpty)
                || (kind == .outgoing && store.indexedOutgoingLinks.isEmpty)
                || (kind == .backlinks && store.indexedBacklinks.isEmpty) {
                Text(empty).foregroundStyle(.tertiary)
            } else {
                content()
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum MetadataKind {
        case outline
        case outgoing
        case backlinks
    }

    private var wordCount: Int {
        store.draftMarkdown.split { $0.isWhitespace || $0.isNewline }.count
    }

    private func openTableEditor(existingOnly: Bool) {
        let sourceSelection = editorSession.mode == .source ? editorController.selectedRange : nil
        let location = sourceSelection?.location ?? 0
        if existingOnly {
            tableContext = MarkdownInteractiveEditor().table(
                in: store.draftMarkdown,
                nearUTF16Location: location
            )
        } else {
            tableContext = MarkdownInteractiveEditor().newTable(
                in: store.draftMarkdown,
                replacingUTF16Range: sourceSelection
                    ?? NSRange(location: store.draftMarkdown.utf16.count, length: 0),
                headerPrefix: store.text("defaultColumn")
            )
        }
    }
}
