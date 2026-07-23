import SwiftUI

struct VaultCommands: Commands {
    @ObservedObject var store: VaultStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(store.text("newNote")) { store.createNote() }
                .keyboardShortcut("n", modifiers: .command)
            Button(store.text("newFolder")) { store.createFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button(store.text("openVault")) { openVault() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button(store.text("createVault")) { createVault() }
        }

        CommandGroup(after: .saveItem) {
            Button(store.text("saveMarkdown")) { _ = store.saveCurrentNote() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(store.currentNote == nil || !store.isModified)
        }

        CommandMenu(store.text("vault")) {
            Button(store.text("refreshDisk")) { store.refresh() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button(store.text("rebuildManifest")) { store.rebuildFileManifest() }
            Button(store.text("rebuildSearchIndex")) { store.rebuildMetadataIndex() }
            Divider()
            Button(store.text("revealSelected")) { store.reveal() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button(store.text("duplicateSelected")) {
                if let path = store.selectedNotePath { store.duplicate(path) }
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(store.selectedNotePath == nil)
            Button(store.text("moveSelectedTrash")) {
                if let path = store.selectedNotePath { store.trash(path) }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(store.selectedNotePath == nil)
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
