import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibrarySidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } content: {
            NotesListView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 330, max: 440)
        } detail: {
            NoteEditorView()
        }
        .navigationSplitViewStyle(.balanced)
        .alert(item: $store.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
