import NotesCore
import SwiftUI

struct VaultSettingsView: View {
    @EnvironmentObject private var store: VaultStore
    @State private var appDraft = AppSettings()
    @State private var vaultDraft = VaultSettings()

    private let fonts = ["System", "Helvetica Neue", "Avenir Next", "Menlo", "SF Mono", "Georgia"]

    var body: some View {
        TabView {
            Form {
                Toggle(text("autoSaveMarkdown"), isOn: $appDraft.autoSave)
                Picker(text("language"), selection: $appDraft.language) {
                    Text(text("russian")).tag(AppLanguage.russian)
                    Text(text("english")).tag(AppLanguage.english)
                }
                saveAppSettingsButton
            }
            .padding(20)
            .tabItem { Label(text("general"), systemImage: "gearshape") }

            Form {
                Picker(text("theme"), selection: $appDraft.theme) {
                    Text(text("system")).tag(AppTheme.system)
                    Text(text("light")).tag(AppTheme.light)
                    Text(text("dark")).tag(AppTheme.dark)
                }
                .pickerStyle(.segmented)

                Picker(text("font"), selection: $appDraft.fontFamily) {
                    ForEach(fonts, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Text(text("fontSize"))
                    Slider(value: $appDraft.fontSize, in: 10...28, step: 1)
                    Text("\(Int(appDraft.fontSize))").monospacedDigit()
                }
                saveAppSettingsButton
            }
            .padding(20)
            .tabItem { Label(text("appearance"), systemImage: "paintbrush") }

            Form {
                Picker(text("newNotes"), selection: $vaultDraft.newNoteLocation) {
                    Text(text("vaultRoot")).tag(NewNoteLocation.vaultRoot)
                    Text(text("currentFolder")).tag(NewNoteLocation.currentFolder)
                    Text(text("specifiedFolder")).tag(NewNoteLocation.specifiedFolder)
                }
                if vaultDraft.newNoteLocation == .specifiedFolder {
                    TextField(text("folderRelativeVault"), text: $vaultDraft.newNoteFolder)
                }

                Picker(text("attachments"), selection: $vaultDraft.attachmentLocation) {
                    Text(text("vaultRoot")).tag(AttachmentLocation.vaultRoot)
                    Text(text("sameFolderAsNote")).tag(AttachmentLocation.sameFolder)
                    Text(text("subfolderNextToNote")).tag(AttachmentLocation.subfolder)
                    Text(text("specifiedFolder")).tag(AttachmentLocation.specifiedFolder)
                }
                if vaultDraft.attachmentLocation == .subfolder {
                    TextField(text("subfolderName"), text: $vaultDraft.attachmentSubfolderName)
                } else if vaultDraft.attachmentLocation == .specifiedFolder {
                    TextField(text("folderRelativeVault"), text: $vaultDraft.attachmentFolder)
                }

                HStack {
                    Spacer()
                    Button(text("saveVaultSettings")) { store.applyVaultSettings(vaultDraft) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .tabItem { Label(text("filesSettings"), systemImage: "folder") }

            VStack(alignment: .leading, spacing: 14) {
                Text(text("currentMarkdownVault")).font(.headline)
                Text(store.vaultURL?.path ?? text("noVault"))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button(text("openAnotherVault")) { openVault() }
                    Button(text("revealFinder")) { store.reveal(.root) }
                    Button(text("rebuildManifest")) { store.rebuildFileManifest() }
                    Button(text("rebuildSearchIndex")) { store.rebuildMetadataIndex() }
                }
                Text(store.indexStatus.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(text("notesappMetadataHint"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(22)
            .tabItem { Label(text("vault"), systemImage: "externaldrive") }

            VStack(alignment: .leading, spacing: 14) {
                Text(text("legacyMigration"))
                    .font(.headline)
                Text(text("legacyMigrationHint"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let info = store.legacyStoreInfo {
                    Text(info.databaseURL.path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    HStack(spacing: 18) {
                        Label(L10n.format("activeCount", language: appDraft.language, info.activeNoteCount), systemImage: "doc.text")
                        Label(L10n.format("deletedCount", language: appDraft.language, info.deletedNoteCount), systemImage: "trash")
                        Label(L10n.format("tagsCount", language: appDraft.language, info.tagCount), systemImage: "tag")
                    }
                    .font(.callout)
                } else {
                    Text(text("noLegacyStore"))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(text("chooseLegacyFolder")) {
                        if let url = PlatformServices.chooseLegacyDataDirectory(
                            startingAt: store.legacyStoreInfo?.databaseURL.deletingLastPathComponent()
                        ) {
                            store.inspectLegacyStore(at: url)
                        }
                    }
                    Button(text("dryRun")) { store.runLegacyMigration(dryRun: true) }
                        .disabled(store.legacyStoreInfo == nil || store.isMigrating)
                    Button(text("backupImport")) { store.runLegacyMigration(dryRun: false) }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.legacyStoreInfo == nil || store.isMigrating)
                    Button(text("undoLastImport")) { store.undoLegacyMigration() }
                        .disabled(store.legacyStoreInfo == nil || store.isMigrating)
                }

                if store.isMigrating { ProgressView().controlSize(.small) }
                if let message = store.migrationStatusMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let report = store.migrationReport {
                    Text(L10n.format("reportItems", language: appDraft.language, report.items.count))
                        .font(.subheadline.bold())
                    List(report.items.prefix(8)) { item in
                        HStack {
                            Image(systemName: item.status == .failed ? "exclamationmark.triangle" : "checkmark.circle")
                            Text(item.title).lineLimit(1)
                            Spacer()
                            Text(text("migrationStatus.\(item.status.rawValue)"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 100)
                }
                Spacer()
            }
            .padding(22)
            .tabItem { Label(text("migration"), systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 660, height: 480)
        .onAppear {
            appDraft = store.appSettings
            vaultDraft = store.vaultSettings
        }
    }

    private var saveAppSettingsButton: some View {
        HStack {
            Spacer()
            Button(text("save")) { store.applyAppSettings(appDraft) }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func openVault() {
        guard let url = PlatformServices.chooseVaultDirectory(startingAt: store.vaultURL?.deletingLastPathComponent()) else { return }
        do {
            try store.activateVault(at: url)
            vaultDraft = store.vaultSettings
        } catch {
            store.alert = VaultAlert(title: text("openVaultTitle"), message: error.localizedDescription)
        }
    }

    private func text(_ key: String) -> String {
        L10n.text(key, language: appDraft.language)
    }
}
