import NotesCore
import SwiftUI

struct NotesListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var noteToDelete: Note?

    private var selection: Binding<Int64?> {
        Binding(
            get: { store.selectedNoteID },
            set: { store.selectNote($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title2.bold())
                Spacer()
                Text(store.format("items", store.notes.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if store.notes.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: store.librarySelection == .trash ? "trash" : "note.text")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text(store.text("noNotes"))
                        .font(.headline)
                    Text(store.text("noNotesHint"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: selection) {
                    ForEach(store.notes) { note in
                        NoteRow(note: note)
                            .tag(note.id)
                            .contextMenu {
                                if note.isDeleted {
                                    Button(store.text("restore")) {
                                        store.restore(note)
                                    }
                                    Button(store.text("deletePermanently"), role: .destructive) {
                                        noteToDelete = note
                                    }
                                } else {
                                    Button(note.isPinned ? store.text("unpin") : store.text("pin")) {
                                        store.togglePinned(note)
                                    }
                                    Divider()
                                    Button(store.text("delete"), role: .destructive) {
                                        store.moveToTrashOrDelete(note)
                                    }
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $store.searchText, prompt: Text(store.text("searchPlaceholder")))
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    ForEach(NoteSorting.allCases) { sorting in
                        Button {
                            store.setSorting(sorting)
                        } label: {
                            if sorting == store.sorting {
                                Label(store.sortingTitle(sorting), systemImage: "checkmark")
                            } else {
                                Text(store.sortingTitle(sorting))
                            }
                        }
                    }
                } label: {
                    Label(store.text("sort"), systemImage: "arrow.up.arrow.down")
                }

                Button {
                    store.createNote()
                } label: {
                    Label(store.text("newNote"), systemImage: "square.and.pencil")
                }
            }
        }
        .alert(
            noteToDelete.map { store.format("deleteNoteQuestion", $0.title) } ?? store.text("deletePermanently"),
            isPresented: Binding(
                get: { noteToDelete != nil },
                set: { if !$0 { noteToDelete = nil } }
            ),
            presenting: noteToDelete
        ) { note in
            Button(store.text("deletePermanently"), role: .destructive) {
                store.moveToTrashOrDelete(note)
                noteToDelete = nil
            }
            Button(store.text("cancel"), role: .cancel) {
                noteToDelete = nil
            }
        } message: { _ in
            Text(store.text("permanentWarning"))
        }
    }

    private var title: String {
        switch store.librarySelection {
        case .all:
            return store.text("allNotes")
        case .trash:
            return store.text("trash")
        case .tag(let tagID):
            return store.tags.first(where: { $0.id == tagID })?.name ?? store.text("tags")
        }
    }
}

private struct NoteRow: View {
    @EnvironmentObject private var store: AppStore
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if note.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(note.title.isEmpty ? store.text("untitled") : note.title)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(note.updatedAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                let preview = RichTextCodec.plainText(from: note.content)
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                Text(preview.isEmpty ? " " : preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if !note.tags.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(note.tags.prefix(3)) { tag in
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color(hex: tag.colorHex))
                                    .frame(width: 6, height: 6)
                                Text(tag.name)
                                    .lineLimit(1)
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
