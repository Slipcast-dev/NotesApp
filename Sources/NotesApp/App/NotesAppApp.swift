import NotesCore
import SwiftUI

@main
struct NotesAppApp: App {
    @StateObject private var store = VaultStore()

    var body: some Scene {
        WindowGroup("NotesApp") {
            VaultContentView()
                .environmentObject(store)
                .preferredColorScheme(colorScheme)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    PlatformServices.activateApplication()
                }
        }
        .defaultSize(width: 1220, height: 760)
        .commands {
            VaultCommands(store: store)
        }

        Settings {
            VaultSettingsView()
                .environmentObject(store)
                .preferredColorScheme(colorScheme)
        }
    }

    private var colorScheme: ColorScheme? {
        switch store.appSettings.theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
