import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum PlatformServices {
    static func activateApplication() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func openSettings() {
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    static func chooseStorageDirectory(startingAt currentDirectory: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "NotesApp"
        panel.prompt = "Choose"
        panel.directoryURL = currentDirectory
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseVaultDirectory(startingAt currentDirectory: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Markdown Vault"
        panel.message = "Choose a folder containing Markdown notes. NotesApp will not convert or move it."
        panel.prompt = "Open Vault"
        panel.directoryURL = currentDirectory
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseLegacyDataDirectory(startingAt currentDirectory: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Legacy NotesApp Data"
        panel.message = "Select the folder containing notes.db. It will be read without modifying the original data."
        panel.prompt = "Analyze"
        panel.directoryURL = currentDirectory
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func createVaultDirectory(startingAt currentDirectory: URL?) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Create Markdown Vault"
        panel.message = "Choose a name and location for the new vault folder."
        panel.prompt = "Create Vault"
        panel.directoryURL = currentDirectory
        panel.nameFieldStringValue = "My Vault"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func chooseAttachmentFiles(startingAt currentDirectory: URL?) -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Attach files"
        panel.prompt = "Attach"
        panel.directoryURL = currentDirectory
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        return panel.runModal() == .OK ? panel.urls : []
    }
}
