import NotesCore
import SwiftUI

struct NoteEditorView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var editorController = RichTextEditorController()
    @State private var showsTagPicker = false
    @State private var showsLinkPicker = false
    @State private var linkableNotes: [Note] = []
    @State private var noteToDelete: Note?

    var body: some View {
        Group {
            if let note = store.currentNote {
                editor(note)
            } else {
                EmptyEditorView()
            }
        }
        .navigationTitle(store.currentNote?.title ?? store.text("notes"))
        .toolbar {
            if let note = store.currentNote {
                ToolbarItemGroup(placement: .primaryAction) {
                    if note.isDeleted {
                        Button {
                            store.restore(note)
                        } label: {
                            Label(store.text("restore"), systemImage: "arrow.uturn.backward")
                        }
                    } else {
                        Button {
                            store.togglePinned(note)
                        } label: {
                            Label(
                                note.isPinned ? store.text("unpin") : store.text("pin"),
                                systemImage: note.isPinned ? "pin.slash" : "pin"
                            )
                        }
                    }

                    Button {
                        store.saveCurrentNote()
                    } label: {
                        Label(store.text("save"), systemImage: "square.and.arrow.down")
                    }
                    .disabled(!store.isModified)

                    Button(role: .destructive) {
                        noteToDelete = note
                    } label: {
                        Label(
                            note.isDeleted ? store.text("deletePermanently") : store.text("delete"),
                            systemImage: "trash"
                        )
                    }
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    PlatformServices.openSettings()
                } label: {
                    Label(store.text("settings"), systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showsTagPicker) {
            TagPickerSheet(
                attachedTagIDs: Set(store.currentNote?.tags.map(\.id) ?? []),
                onSelect: { tag in
                    store.addTagToCurrentNote(tag)
                },
                onCreate: { name, color in
                    store.createTag(name: name, colorHex: color)
                    if let tag = store.tags.first(where: {
                        $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                    }) {
                        store.addTagToCurrentNote(tag)
                    }
                }
            )
            .environmentObject(store)
        }
        .sheet(isPresented: $showsLinkPicker) {
            InternalLinkPickerSheet(notes: linkableNotes) { note in
                editorController.insertInternalLink(title: note.title)
            }
            .environmentObject(store)
        }
        .alert(
            noteToDelete.map { store.format("deleteNoteQuestion", $0.title) } ?? store.text("delete"),
            isPresented: Binding(
                get: { noteToDelete != nil },
                set: { if !$0 { noteToDelete = nil } }
            ),
            presenting: noteToDelete
        ) { note in
            Button(note.isDeleted ? store.text("deletePermanently") : store.text("delete"), role: .destructive) {
                store.moveToTrashOrDelete(note)
                noteToDelete = nil
            }
            Button(store.text("cancel"), role: .cancel) {
                noteToDelete = nil
            }
        } message: { note in
            if note.isDeleted {
                Text(store.text("permanentWarning"))
            }
        }
    }

    private func editor(_ note: Note) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                TextField(store.text("untitled"), text: $store.draftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 28, weight: .bold))

                HStack(spacing: 6) {
                    ForEach(note.tags) { tag in
                        Button {
                            store.removeTagFromCurrentNote(tag)
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color(hex: tag.colorHex))
                                    .frame(width: 7, height: 7)
                                Text(tag.name)
                                Image(systemName: "xmark")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: tag.colorHex).opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(store.text("removeTag"))
                    }

                    Button {
                        showsTagPicker = true
                    } label: {
                        Label(store.text("addTag"), systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            formattingBar
                .padding(.horizontal, 12)
                .padding(.vertical, 7)

            Divider()

            RichTextEditor(
                content: $store.draftContent,
                fontFamily: store.settings.fontFamily,
                fontSize: store.settings.fontSize,
                controller: editorController
            )
            .id(note.id)

            Divider()

            HStack {
                Image(systemName: store.isModified ? "circle.fill" : "checkmark.circle")
                    .foregroundStyle(store.isModified ? Color.orange : Color.secondary)
                Text(store.isModified ? store.text("unsaved") : store.text("saved"))
                Spacer()
                Text("\(store.text("updated")): \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private var formattingBar: some View {
        HStack(spacing: 4) {
            Group {
                Button {
                    editorController.toggleBold()
                } label: {
                    Image(systemName: "bold")
                }
                .help(store.text("bold"))

                Button {
                    editorController.toggleItalic()
                } label: {
                    Image(systemName: "italic")
                }
                .help(store.text("italic"))

                Button {
                    editorController.applyHeading()
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .help(store.text("heading"))
            }
            .buttonStyle(.borderless)

            Divider().frame(height: 18)

            Group {
                Button {
                    editorController.insertChecklist()
                } label: {
                    Image(systemName: "checklist")
                }
                .help(store.text("checklist"))

                Button {
                    editorController.toggleChecklistItem()
                } label: {
                    Image(systemName: "checkmark.square")
                }
                .help(store.text("toggleChecklist"))

                Button {
                    editorController.insertTable()
                } label: {
                    Image(systemName: "tablecells")
                }
                .help(store.text("table"))
            }
            .buttonStyle(.borderless)

            Divider().frame(height: 18)

            Button {
                linkableNotes = store.linkableNotes()
                if linkableNotes.isEmpty {
                    store.alert = AppAlert(title: store.text("internalLink"), message: store.text("noLinkableNotes"))
                } else {
                    showsLinkPicker = true
                }
            } label: {
                Image(systemName: "link.badge.plus")
            }
            .buttonStyle(.borderless)
            .help(store.text("insertLink"))

            Button {
                if let title = editorController.selectedInternalLinkTitle() {
                    store.openInternalLink(title: title)
                }
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help(store.text("openLink"))

            Spacer()

            Menu {
                Button(store.text("uppercase")) {
                    editorController.transformSelection { $0.uppercased() }
                }
                Button(store.text("lowercase")) {
                    editorController.transformSelection { $0.lowercased() }
                }
            } label: {
                Label(store.text("format"), systemImage: "textformat")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .controlSize(.small)
    }
}

private struct EmptyEditorView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "note.text")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(store.text("selectNote"))
                .font(.title2.bold())
            Text(store.text("selectNoteHint"))
                .foregroundStyle(.secondary)
            Button(store.text("newNote")) {
                store.createNote()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TagPickerSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let attachedTagIDs: Set<Int64>
    let onSelect: (Tag) -> Void
    let onCreate: (String, String) -> Void

    @State private var newName = ""
    @State private var newColor = Color(hex: Tag.defaultColorHex)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.text("addTag"))
                .font(.title2.bold())

            List {
                ForEach(store.tags.filter { !attachedTagIDs.contains($0.id) }) { tag in
                    Button {
                        onSelect(tag)
                        dismiss()
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hex: tag.colorHex))
                                .frame(width: 9, height: 9)
                            Text(tag.name)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minHeight: 130)

            Divider()

            HStack {
                TextField(store.text("tagName"), text: $newName)
                ColorPicker("", selection: $newColor, supportsOpacity: false)
                    .labelsHidden()
                Button(store.text("create")) {
                    onCreate(newName, newColor.hexRGB)
                    dismiss()
                }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack {
                Spacer()
                Button(store.text("cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 400, height: 360)
    }
}

private struct InternalLinkPickerSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let notes: [Note]
    let onSelect: (Note) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.text("insertLink"))
                .font(.title2.bold())
            List(notes) { note in
                Button(note.title) {
                    onSelect(note)
                    dismiss()
                }
                .buttonStyle(.plain)
            }
            HStack {
                Spacer()
                Button(store.text("cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 390, height: 380)
    }
}
