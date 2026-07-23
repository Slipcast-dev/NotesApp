import SwiftUI

struct NotesCommands: Commands {
    @ObservedObject var store: AppStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(store.text("newNote")) {
                store.createNote()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu(store.text("notes")) {
            Button(store.text("save")) {
                store.saveCurrentNote()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(store.currentNote == nil || !store.isModified)

            Divider()

            Button(store.currentNote?.isPinned == true ? store.text("unpin") : store.text("pin")) {
                if let note = store.currentNote {
                    store.togglePinned(note)
                }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(store.currentNote == nil || store.currentNote?.isDeleted == true)

            Button(store.text("delete")) {
                if let note = store.currentNote, !note.isDeleted {
                    store.moveToTrashOrDelete(note)
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(store.currentNote == nil || store.currentNote?.isDeleted == true)
        }
    }
}
