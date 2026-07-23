import NotesCore
import SwiftUI

struct LibrarySidebarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showsNewTag = false
    @State private var colorTag: Tag?
    @State private var deleteTag: Tag?

    private var selection: Binding<LibrarySelection?> {
        Binding(
            get: { store.librarySelection },
            set: { value in
                if let value {
                    store.changeLibrarySelection(to: value)
                }
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section(store.text("library")) {
                Label {
                    HStack {
                        Text(store.text("allNotes"))
                        Spacer()
                        Text("\(store.activeCount)")
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "note.text")
                }
                .tag(LibrarySelection.all)

                Label {
                    HStack {
                        Text(store.text("trash"))
                        Spacer()
                        if store.trashCount > 0 {
                            Text("\(store.trashCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "trash")
                }
                .tag(LibrarySelection.trash)
            }

            Section {
                ForEach(store.tags) { tag in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(Color(hex: tag.colorHex))
                            .frame(width: 9, height: 9)
                        Text(tag.name)
                            .lineLimit(1)
                    }
                    .tag(LibrarySelection.tag(tag.id))
                    .contextMenu {
                        Button(store.text("changeColor")) {
                            colorTag = tag
                        }
                        Divider()
                        Button(store.text("delete"), role: .destructive) {
                            deleteTag = tag
                        }
                    }
                }
            } header: {
                HStack {
                    Text(store.text("tags"))
                    Spacer()
                    Button {
                        showsNewTag = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help(store.text("newTag"))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(store.text("appName"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsNewTag = true
                } label: {
                    Label(store.text("newTag"), systemImage: "tag.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showsNewTag) {
            TagEditorSheet(
                title: store.text("newTag"),
                initialName: "",
                initialColor: Tag.defaultColorHex,
                allowsNameEditing: true
            ) { name, color in
                store.createTag(name: name, colorHex: color)
            }
            .environmentObject(store)
        }
        .sheet(item: $colorTag) { tag in
            TagEditorSheet(
                title: store.text("changeColor"),
                initialName: tag.name,
                initialColor: tag.colorHex,
                allowsNameEditing: false
            ) { _, color in
                store.updateTagColor(tag, colorHex: color)
            }
            .environmentObject(store)
        }
        .alert(
            deleteTag.map { store.format("deleteTagQuestion", $0.name) } ?? store.text("delete"),
            isPresented: Binding(
                get: { deleteTag != nil },
                set: { if !$0 { deleteTag = nil } }
            ),
            presenting: deleteTag
        ) { tag in
            Button(store.text("delete"), role: .destructive) {
                store.deleteTag(tag)
                deleteTag = nil
            }
            Button(store.text("cancel"), role: .cancel) {
                deleteTag = nil
            }
        }
    }
}

struct TagEditorSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let title: String
    let allowsNameEditing: Bool
    let onSave: (String, String) -> Void

    @State private var name: String
    @State private var color: Color

    init(
        title: String,
        initialName: String,
        initialColor: String,
        allowsNameEditing: Bool,
        onSave: @escaping (String, String) -> Void
    ) {
        self.title = title
        self.allowsNameEditing = allowsNameEditing
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _color = State(initialValue: Color(hex: initialColor))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.bold())

            if allowsNameEditing {
                TextField(store.text("tagName"), text: $name)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(name)
                    .font(.headline)
            }

            ColorPicker(store.text("changeColor"), selection: $color, supportsOpacity: false)

            HStack {
                Spacer()
                Button(store.text("cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(allowsNameEditing ? store.text("create") : store.text("save")) {
                    onSave(name, color.hexRGB)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
