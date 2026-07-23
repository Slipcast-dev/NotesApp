import NotesCore
import SwiftUI
import UniformTypeIdentifiers

struct VaultSidebarView: View {
    @EnvironmentObject private var store: VaultStore
    let onRename: (NotePath) -> Void
    let onTrash: (NotePath) -> Void

    var body: some View {
        List {
            Section {
                Button {
                    store.selectFolder(.root)
                } label: {
                    Label {
                        HStack {
                            Text(store.text("allNotes"))
                            Spacer()
                            Text("\(store.notes.count)").foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "note.text")
                    }
                }
                .buttonStyle(.plain)
            }

            Section(store.text("files")) {
                ForEach(store.tree) { item in
                    VaultTreeNodeView(item: item, onRename: onRename, onTrash: onTrash)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(store.vault?.name ?? "NotesApp")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.createNote()
                } label: {
                    Label(store.text("newNote"), systemImage: "square.and.pencil")
                }

                Menu {
                    Button(store.text("newFolder")) { store.createFolder() }
                    Divider()
                    Button(store.text("openVault")) { openVault() }
                    Button(store.text("createVault")) { createVault() }
                    Divider()
                    Button(store.text("revealVault")) { store.reveal(.root) }
                    Button(store.text("rebuildManifest")) { store.rebuildFileManifest() }
                } label: {
                    Label(store.text("vaultActions"), systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private func openVault() {
        guard let url = PlatformServices.chooseVaultDirectory(startingAt: store.vaultURL?.deletingLastPathComponent()) else { return }
        do { try store.activateVault(at: url) } catch {
            store.alert = VaultAlert(title: store.text("openVaultTitle"), message: error.localizedDescription)
        }
    }

    private func createVault() {
        do {
            guard let url = try PlatformServices.createVaultDirectory(startingAt: store.vaultURL?.deletingLastPathComponent()) else { return }
            try store.activateVault(at: url)
        } catch {
            store.alert = VaultAlert(title: store.text("createVaultTitle"), message: error.localizedDescription)
        }
    }
}

private struct VaultTreeNodeView: View {
    @EnvironmentObject private var store: VaultStore
    let item: VaultItem
    let onRename: (NotePath) -> Void
    let onTrash: (NotePath) -> Void
    @State private var isExpanded = true
    @State private var isDropTargeted = false

    var body: some View {
        if item.isFolder {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(item.children) { child in
                    VaultTreeNodeView(item: child, onRename: onRename, onTrash: onTrash)
                }
            } label: {
                row
            }
            .onDrop(of: [UTType.utf8PlainText], isTargeted: $isDropTargeted) { providers in
                acceptDrop(providers, folder: item.path)
            }
        } else {
            row
        }
    }

    private var row: some View {
        Button {
            store.selectItem(item)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: iconName)
                    .foregroundStyle(item.kind == .attachment ? .secondary : .primary)
                Text(item.displayName)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrag {
            NSItemProvider(object: item.path.value as NSString)
        }
        .contextMenu {
            if item.isFolder {
                Button(store.text("newNoteHere")) { store.createNote(in: item.path) }
                Button(store.text("newFolderHere")) { store.createFolder(in: item.path) }
                Divider()
            }
            Button(store.text("rename")) { onRename(item.path) }
            Button(store.text("duplicate")) { store.duplicate(item.path) }
            Button(store.text("revealFinder")) { store.reveal(item.path) }
            Divider()
            Button(store.text("moveTrash"), role: .destructive) { onTrash(item.path) }
        }
    }

    private var iconName: String {
        switch item.kind {
        case .folder: return isExpanded ? "folder.fill" : "folder"
        case .note: return "doc.text"
        case .attachment: return "paperclip"
        }
    }

    private func acceptDrop(_ providers: [NSItemProvider], folder: NotePath) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let raw = value as? String, let path = try? NotePath(raw), store.contains(path) else { return }
            DispatchQueue.main.async { store.move(path, into: folder) }
        }
        return true
    }
}
