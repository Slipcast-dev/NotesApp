import NotesCore
import SwiftUI

struct VaultContentView: View {
    @EnvironmentObject private var store: VaultStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var renameRequest: VaultRenameRequest?
    @State private var trashRequest: NotePath?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VaultSidebarView(
                onRename: { renameRequest = VaultRenameRequest(path: $0) },
                onTrash: { trashRequest = $0 }
            )
            .navigationSplitViewColumnWidth(min: 210, ideal: 260, max: 360)
        } content: {
            VaultNotesListView(
                onRename: { renameRequest = VaultRenameRequest(path: $0) },
                onTrash: { trashRequest = $0 }
            )
            .navigationSplitViewColumnWidth(min: 250, ideal: 330, max: 460)
        } detail: {
            VaultNoteEditorView(
                onRename: { renameRequest = VaultRenameRequest(path: $0) },
                onTrash: { trashRequest = $0 }
            )
        }
        .navigationSplitViewStyle(.balanced)
        .alert(item: $store.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text(store.text("ok"))))
        }
        .alert(store.text("externalConflict"), isPresented: conflictIsPresented) {
            Button(store.text("reloadDisk")) { store.reloadConflictFromDisk() }
            Button(store.text("overwriteMine"), role: .destructive) { store.overwriteConflict() }
            Button(store.text("keepEditing"), role: .cancel) { store.conflict = nil }
        } message: {
            if store.conflict?.reason == .removed {
                Text(store.text("removedExternalMessage"))
            } else {
                Text(store.text("changedExternalMessage"))
            }
        }
        .sheet(item: $renameRequest) { request in
            VaultRenameSheet(request: request) { newName in
                store.rename(request.path, to: newName)
            }
        }
        .alert(store.text("moveItemTrashQuestion"), isPresented: trashIsPresented) {
            Button(store.text("moveTrash"), role: .destructive) {
                if let path = trashRequest { store.trash(path) }
                trashRequest = nil
            }
            Button(store.text("cancel"), role: .cancel) { trashRequest = nil }
        } message: {
            Text(trashRequest?.value ?? "")
        }
    }

    private var conflictIsPresented: Binding<Bool> {
        Binding(
            get: { store.conflict != nil },
            set: { if !$0 { store.conflict = nil } }
        )
    }

    private var trashIsPresented: Binding<Bool> {
        Binding(
            get: { trashRequest != nil },
            set: { if !$0 { trashRequest = nil } }
        )
    }
}

struct VaultRenameRequest: Identifiable {
    let path: NotePath
    var id: String { path.value }
}

private struct VaultRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: VaultStore
    let request: VaultRenameRequest
    let onRename: (String) -> Void
    @State private var name: String

    init(request: VaultRenameRequest, onRename: @escaping (String) -> Void) {
        self.request = request
        self.onRename = onRename
        let initial = request.path.pathExtension.lowercased() == "md"
            ? request.path.deletingPathExtension
            : request.path.name
        _name = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.text("rename"))
                .font(.title2.bold())
            Text(request.path.value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            TextField(store.text("name"), text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(store.text("cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(store.text("rename")) {
                    onRename(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
