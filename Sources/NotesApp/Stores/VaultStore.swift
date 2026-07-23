import Combine
import Foundation
import NotesCore

struct VaultAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct VaultConflict: Identifiable {
    enum Reason {
        case modified
        case removed
    }

    let id = UUID()
    let path: NotePath
    let diskMarkdown: String?
    let reason: Reason
}

struct VaultIndexStatus: Equatable {
    enum Phase: Equatable {
        case idle
        case indexing
        case ready
        case failed
    }

    var phase: Phase = .idle
    var completed = 0
    var total = 0
    var message = ""
}

final class VaultStore: ObservableObject {
    @Published private(set) var vault: Vault?
    @Published private(set) var tree: [VaultItem] = []
    @Published private(set) var notes: [VaultNoteMetadata] = []
    @Published private(set) var selectedFolder: NotePath = .root
    @Published private(set) var selectedNotePath: NotePath?
    @Published private(set) var currentNote: VaultNote?
    @Published var draftMarkdown = "" {
        didSet { draftDidChange() }
    }
    @Published private(set) var isModified = false
    @Published var searchText = "" {
        didSet { scheduleSearch() }
    }
    @Published private(set) var searchResults: [SearchResult] = []
    @Published private(set) var indexedHeadings: [IndexedHeading] = []
    @Published private(set) var indexedBacklinks: [IndexedBacklink] = []
    @Published private(set) var indexedOutgoingLinks: [MarkdownLinkReference] = []
    @Published private(set) var indexStatus = VaultIndexStatus()
    @Published private(set) var vaultSettings = VaultSettings()
    @Published private(set) var appSettings = AppSettings()
    @Published private(set) var legacyStoreInfo: LegacyStoreInfo?
    @Published private(set) var migrationReport: MigrationReport?
    @Published private(set) var migrationStatusMessage: String?
    @Published private(set) var isMigrating = false
    @Published var alert: VaultAlert?
    @Published var conflict: VaultConflict?

    private let bookmarkStore: SecurityScopedBookmarkStore
    private let fileMonitor: FileChangeMonitor
    private let appSettingsService: SettingsService
    private let migrationService = MigrationService()
    private var fileService: VaultFileService?
    private var metadataIndex: MetadataIndex?
    private var searchIndex: SearchIndex?
    private var scopedURL: URL?
    private var isAccessingSecurityScope = false
    private var isLoadingDraft = false
    private var saveTimer: Timer?
    private var indexingTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    init(
        bookmarkStore: SecurityScopedBookmarkStore = SecurityScopedBookmarkStore(),
        fileMonitor: FileChangeMonitor = FileChangeMonitor()
    ) {
        self.bookmarkStore = bookmarkStore
        self.fileMonitor = fileMonitor

        let supportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NotesApp", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("NotesApp", isDirectory: true)
        appSettingsService = SettingsService(directory: supportRoot.appendingPathComponent("Preferences", isDirectory: true))
        appSettings = appSettingsService.load()

        let environmentVault = ProcessInfo.processInfo.environment["NOTESAPP_VAULT_DIR"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        let initialURL = environmentVault
            ?? bookmarkStore.restoreLast()
            ?? supportRoot.appendingPathComponent("Vault", isDirectory: true)
        do {
            try activateVault(at: initialURL, remember: true)
        } catch {
            present(error)
        }

        let legacyDirectory = supportRoot.appendingPathComponent("Data", isDirectory: true)
        if FileManager.default.fileExists(atPath: legacyDirectory.appendingPathComponent("notes.db").path) {
            inspectLegacyStore(at: legacyDirectory)
        }
    }

    deinit {
        saveTimer?.invalidate()
        fileMonitor.stop()
        if isAccessingSecurityScope {
            scopedURL?.stopAccessingSecurityScopedResource()
        }
    }

    var visibleNotes: [VaultNoteMetadata] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let resultPaths = Set(searchResults.map(\.path))
        return notes.filter { note in
            let inFolder = selectedFolder.isRoot
                || note.path.parent == selectedFolder
                || note.path.isDescendant(of: selectedFolder)
            let matchesSearch = query.isEmpty || resultPaths.contains(note.path)
            return inFolder && matchesSearch
        }
    }

    var vaultURL: URL? { vault?.rootURL }

    func text(_ key: String) -> String {
        L10n.text(key, language: appSettings.language)
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }

    func activateVault(at url: URL, remember: Bool = true) throws {
        guard saveCurrentNote() else { return }
        stopCurrentVault()

        let normalized = url.standardizedFileURL
        let access = normalized.startAccessingSecurityScopedResource()
        do {
            let service = try VaultFileService(rootURL: normalized)
            let metadataIndex = try MetadataIndex(vaultURL: normalized)
            let searchIndex = try SearchIndex(vaultURL: normalized)
            fileService = service
            self.metadataIndex = metadataIndex
            self.searchIndex = searchIndex
            vault = service.vault
            scopedURL = normalized
            isAccessingSecurityScope = access
            vaultSettings = service.loadSettings()
            selectedFolder = .root
            clearSelection()
            try reloadSnapshot(rebuildManifest: true)
            if remember { try bookmarkStore.save(normalized) }
            fileMonitor.start(vaultURL: normalized) { [weak self] in
                self?.externalFilesDidChange()
            }
            scheduleIndexSynchronization()
        } catch {
            if access { normalized.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    func createNote(in explicitFolder: NotePath? = nil) {
        guard saveCurrentNote(), let service = fileService else { return }
        do {
            let folder = try explicitFolder ?? targetFolderForNewNote()
            let path = try service.createNote(in: folder, preferredName: text("untitled"))
            try reloadSnapshot()
            scheduleIndexSynchronization()
            selectNote(path)
        } catch { present(error) }
    }

    func createFolder(in explicitFolder: NotePath? = nil) {
        guard saveCurrentNote(), let service = fileService else { return }
        do {
            let path = try service.createFolder(in: explicitFolder ?? selectedFolder)
            try reloadSnapshot()
            scheduleIndexSynchronization()
            selectedFolder = path
        } catch { present(error) }
    }

    func selectFolder(_ path: NotePath) {
        selectedFolder = path
    }

    func selectItem(_ item: VaultItem) {
        if item.isFolder {
            selectFolder(item.path)
        } else if item.kind == .note {
            selectNote(item.path)
        }
    }

    func selectNote(_ path: NotePath?) {
        guard path != selectedNotePath else { return }
        guard saveCurrentNote() else { return }
        guard let path else {
            clearSelection()
            return
        }
        loadNote(path)
    }

    @discardableResult
    func saveCurrentNote(force: Bool = false) -> Bool {
        saveTimer?.invalidate()
        saveTimer = nil
        guard isModified, let currentNote, let service = fileService else { return true }
        do {
            let saved = try service.writeNote(
                at: currentNote.path,
                markdown: draftMarkdown,
                expectedRevision: currentNote.revision,
                force: force
            )
            setCurrentNote(saved)
            try reloadSnapshot()
            scheduleIndexSynchronization()
            return true
        } catch VaultFileError.externallyModified(let path, let diskMarkdown) {
            conflict = VaultConflict(path: path, diskMarkdown: diskMarkdown, reason: .modified)
            return false
        } catch VaultFileError.externallyRemoved(let path) {
            conflict = VaultConflict(path: path, diskMarkdown: nil, reason: .removed)
            return false
        } catch {
            present(error)
            return false
        }
    }

    func reloadConflictFromDisk() {
        guard let conflict else { return }
        self.conflict = nil
        if conflict.reason == .removed {
            clearSelection()
        } else {
            loadNote(conflict.path)
        }
        refresh()
    }

    func overwriteConflict() {
        guard conflict != nil else { return }
        conflict = nil
        _ = saveCurrentNote(force: true)
    }

    func rename(_ path: NotePath, to newName: String) {
        guard saveCurrentNote(), let service = fileService else { return }
        do {
            let currentPath = selectedNotePath
            let destination = try service.rename(path, to: newName)
            try reloadSnapshot()
            scheduleIndexSynchronization()
            if currentPath == path {
                clearSelection()
                loadNote(destination)
            } else if let currentPath, currentPath.isDescendant(of: path) {
                let suffix = String(currentPath.value.dropFirst(path.value.count + 1))
                let movedCurrentPath = try NotePath(destination.value + "/" + suffix)
                clearSelection()
                loadNote(movedCurrentPath)
            }
            if selectedFolder == path { selectedFolder = destination }
        } catch { present(error) }
    }

    func duplicate(_ path: NotePath) {
        guard saveCurrentNote(), let service = fileService else { return }
        do {
            let duplicate = try service.duplicate(path)
            try reloadSnapshot()
            scheduleIndexSynchronization()
            if duplicate.pathExtension.lowercased() == "md" { selectNote(duplicate) }
        } catch { present(error) }
    }

    func move(_ path: NotePath, into folder: NotePath) {
        guard saveCurrentNote(), let service = fileService else { return }
        do {
            let currentPath = selectedNotePath
            let destination = try service.move(path, into: folder)
            try reloadSnapshot()
            scheduleIndexSynchronization()
            if currentPath == path {
                clearSelection()
                loadNote(destination)
            } else if let currentPath, currentPath.isDescendant(of: path) {
                let suffix = String(currentPath.value.dropFirst(path.value.count + 1))
                let movedCurrentPath = try NotePath(destination.value + "/" + suffix)
                clearSelection()
                loadNote(movedCurrentPath)
            }
        } catch { present(error) }
    }

    func trash(_ path: NotePath) {
        guard saveCurrentNote(), let service = fileService else { return }
        do {
            let removesCurrent = selectedNotePath == path || selectedNotePath?.isDescendant(of: path) == true
            try service.trash(path)
            if removesCurrent { clearSelection() }
            if selectedFolder == path || selectedFolder.isDescendant(of: path) { selectedFolder = .root }
            try reloadSnapshot()
            scheduleIndexSynchronization()
        } catch { present(error) }
    }

    func refresh() {
        do {
            try reloadSnapshot()
            scheduleIndexSynchronization()
        } catch { present(error) }
    }

    func rebuildFileManifest() {
        do { try reloadSnapshot(rebuildManifest: true) } catch { present(error) }
    }

    func rebuildMetadataIndex() {
        guard let metadataIndex else { return }
        indexingTask?.cancel()
        indexStatus = VaultIndexStatus(phase: .indexing, completed: 0, total: notes.count, message: text("rebuildingIndex"))
        let store = self
        indexingTask = Task {
            do {
                let result = try await metadataIndex.rebuild { completed, total in
                    DispatchQueue.main.async {
                        store.indexStatus = VaultIndexStatus(
                            phase: .indexing,
                            completed: completed,
                            total: total,
                            message: store.format("indexingProgress", completed, total)
                        )
                    }
                }
                await MainActor.run {
                    store.indexStatus = VaultIndexStatus(
                        phase: .ready,
                        completed: result.indexed + result.unchanged,
                        total: result.indexed + result.unchanged,
                        message: store.text("indexRebuilt")
                    )
                    store.scheduleSearch()
                    store.refreshIndexedContext()
                }
            } catch is CancellationError {
                await MainActor.run { store.indexStatus.phase = .idle }
            } catch {
                await MainActor.run {
                    store.indexStatus = VaultIndexStatus(phase: .failed, message: error.localizedDescription)
                }
            }
        }
    }

    func cancelIndexing() {
        indexingTask?.cancel()
        indexingTask = nil
        indexStatus = VaultIndexStatus(phase: .idle, message: text("indexingCancelled"))
    }

    func applyVaultSettings(_ settings: VaultSettings) {
        guard let service = fileService else { return }
        do {
            try service.saveSettings(settings)
            vaultSettings = settings
        } catch { present(error) }
    }

    func applyAppSettings(_ settings: AppSettings) {
        do {
            try appSettingsService.save(settings)
            appSettings = settings
            if settings.autoSave, isModified { scheduleSave() }
            if !settings.autoSave { saveTimer?.invalidate() }
        } catch { present(error) }
    }

    func inspectLegacyStore(at directory: URL) {
        do {
            legacyStoreInfo = try migrationService.inspect(sourceDirectory: directory)
            migrationStatusMessage = format("legacyStoreFound", legacyStoreInfo?.noteCount ?? 0)
        } catch {
            legacyStoreInfo = nil
            migrationStatusMessage = error.localizedDescription
        }
    }

    func runLegacyMigration(dryRun: Bool) {
        guard let sourceDirectory = legacyStoreInfo?.databaseURL.deletingLastPathComponent(),
              let targetVaultURL = vaultURL, !isMigrating else { return }
        isMigrating = true
        migrationStatusMessage = dryRun ? text("analyzingMigration") : text("backingUpImporting")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = Result {
                try self.migrationService.migrate(
                    sourceDirectory: sourceDirectory,
                    targetVaultURL: targetVaultURL,
                    dryRun: dryRun
                )
            }
            DispatchQueue.main.async {
                self.isMigrating = false
                switch result {
                case .success(let report):
                    self.migrationReport = report
                    self.migrationStatusMessage = dryRun
                        ? self.format("dryRunComplete", report.items.filter { $0.status == .planned }.count)
                        : self.format("migrationComplete", report.importedCount, report.skippedCount, report.failedCount)
                    if !dryRun { self.refresh() }
                case .failure(let error):
                    self.migrationStatusMessage = error.localizedDescription
                    self.present(error)
                }
            }
        }
    }

    func undoLegacyMigration() {
        guard let sourceDirectory = legacyStoreInfo?.databaseURL.deletingLastPathComponent(),
              let targetVaultURL = vaultURL, !isMigrating else { return }
        isMigrating = true
        migrationStatusMessage = text("checkingUndo")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = Result {
                try self.migrationService.undo(sourceDirectory: sourceDirectory, targetVaultURL: targetVaultURL)
            }
            DispatchQueue.main.async {
                self.isMigrating = false
                switch result {
                case .success(let report):
                    self.migrationStatusMessage = self.format(
                        "undoComplete",
                        report.restoredToUndoFolder.count,
                        report.skippedModifiedFiles.count
                    )
                    self.refresh()
                case .failure(let error):
                    self.migrationStatusMessage = error.localizedDescription
                    self.present(error)
                }
            }
        }
    }

    @MainActor
    func reveal(_ path: NotePath? = nil) {
        guard let service = fileService else { return }
        PlatformServices.revealInFinder(service.url(for: path ?? selectedNotePath ?? .root))
    }

    func contains(_ path: NotePath) -> Bool {
        if path.isRoot { return true }
        return findItem(path, in: tree) != nil
    }

    @MainActor
    func openIndexedLink(_ reference: MarkdownLinkReference) {
        if reference.kind == .markdown,
           let url = URL(string: reference.destination),
           let scheme = url.scheme, ["http", "https", "mailto"].contains(scheme.lowercased()) {
            PlatformServices.openURL(url)
            return
        }
        guard let source = selectedNotePath else { return }
        let resolution = LinkResolver().resolve(reference, from: source, candidates: notes.map(\.path))
        switch resolution {
        case .resolved(let path, _, _):
            selectNote(path)
        case .ambiguous(let target, let candidates):
            alert = VaultAlert(
                title: text("ambiguousLink"),
                message: format("ambiguousLinkMatches", target, candidates.map(\.value).joined(separator: "\n"))
            )
        case .unresolved(let target):
            createUnresolvedNote(target: target, from: source)
        }
    }

    func openBacklink(_ backlink: IndexedBacklink) {
        selectNote(backlink.sourcePath)
    }

    func importAttachments(_ urls: [URL]) -> String? {
        guard let vaultURL, let notePath = selectedNotePath, !urls.isEmpty else { return nil }
        do {
            let attachments = try AttachmentService(vaultURL: vaultURL)
            let embeds = try urls.map { url -> String in
                let path = try attachments.importFile(at: url, for: notePath, settings: vaultSettings)
                return attachments.embedMarkdown(for: path, from: notePath)
            }
            try reloadSnapshot()
            scheduleIndexSynchronization()
            return embeds.joined(separator: "\n")
        } catch {
            present(error)
            return nil
        }
    }

    func importClipboardImage(_ data: Data, fileExtension: String = "png") -> String? {
        guard let vaultURL, let notePath = selectedNotePath else { return nil }
        do {
            let attachments = try AttachmentService(vaultURL: vaultURL)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let name = "\(text("pastedImage")) \(formatter.string(from: Date())).\(fileExtension)"
            let path = try attachments.save(data: data, preferredName: name, for: notePath, settings: vaultSettings)
            try reloadSnapshot()
            scheduleIndexSynchronization()
            return attachments.embedMarkdown(for: path, from: notePath)
        } catch {
            present(error)
            return nil
        }
    }

    private func createUnresolvedNote(target: String, from source: NotePath) {
        guard saveCurrentNote(), let service = fileService else { return }
        do {
            let targetPath: NotePath
            if target.contains("/") {
                let raw = target.lowercased().hasSuffix(".md") ? target : target + ".md"
                targetPath = try NotePath(raw)
                try service.ensureFolder(at: targetPath.parent)
            } else {
                let folder = try targetFolderForNewNote()
                targetPath = try folder.appending(target.lowercased().hasSuffix(".md") ? target : target + ".md")
            }
            if contains(targetPath) {
                selectNote(targetPath)
                return
            }
            let created = try service.createNote(
                in: targetPath.parent,
                preferredName: targetPath.name,
                markdown: ""
            )
            try reloadSnapshot()
            scheduleIndexSynchronization()
            selectNote(created)
        } catch { present(error) }
    }

    private func stopCurrentVault() {
        indexingTask?.cancel()
        searchTask?.cancel()
        fileMonitor.stop()
        if isAccessingSecurityScope { scopedURL?.stopAccessingSecurityScopedResource() }
        isAccessingSecurityScope = false
        scopedURL = nil
        fileService = nil
        metadataIndex = nil
        searchIndex = nil
        searchResults = []
        indexedHeadings = []
        indexedBacklinks = []
        indexedOutgoingLinks = []
    }

    private func targetFolderForNewNote() throws -> NotePath {
        switch vaultSettings.newNoteLocation {
        case .vaultRoot:
            return .root
        case .currentFolder:
            return selectedFolder
        case .specifiedFolder:
            let configured = try NotePath(vaultSettings.newNoteFolder)
            try fileService?.ensureFolder(at: configured)
            return configured
        }
    }

    private func reloadSnapshot(rebuildManifest: Bool = false) throws {
        guard let service = fileService else { return }
        let snapshot = try (rebuildManifest ? service.rebuildFileManifest() : service.snapshot())
        tree = snapshot.tree
        notes = snapshot.notes

        guard let currentNote else { return }
        if !notes.contains(where: { $0.path == currentNote.path }) {
            if isModified {
                conflict = VaultConflict(path: currentNote.path, diskMarkdown: nil, reason: .removed)
            } else {
                clearSelection()
            }
        }
    }

    private func externalFilesDidChange() {
        guard let service = fileService else { return }
        do {
            let oldNote = currentNote
            try reloadSnapshot()
            scheduleIndexSynchronization()
            guard let oldNote, selectedNotePath == oldNote.path,
                  notes.contains(where: { $0.path == oldNote.path }) else { return }
            let diskNote = try service.readNote(at: oldNote.path)
            if diskNote.revision.fingerprint != oldNote.revision.fingerprint {
                if isModified {
                    conflict = VaultConflict(path: oldNote.path, diskMarkdown: diskNote.markdown, reason: .modified)
                } else {
                    setCurrentNote(diskNote)
                }
            }
        } catch { present(error) }
    }

    private func loadNote(_ path: NotePath) {
        guard let service = fileService else { return }
        do {
            setCurrentNote(try service.readNote(at: path))
            selectedFolder = path.parent
            refreshIndexedContext()
        } catch {
            present(error)
            clearSelection()
        }
    }

    private func setCurrentNote(_ note: VaultNote) {
        isLoadingDraft = true
        currentNote = note
        selectedNotePath = note.path
        draftMarkdown = note.markdown
        isModified = false
        isLoadingDraft = false
    }

    private func clearSelection() {
        isLoadingDraft = true
        selectedNotePath = nil
        currentNote = nil
        draftMarkdown = ""
        isModified = false
        isLoadingDraft = false
        saveTimer?.invalidate()
        indexedHeadings = []
        indexedBacklinks = []
        indexedOutgoingLinks = []
    }

    private func draftDidChange() {
        guard !isLoadingDraft, let currentNote else { return }
        isModified = draftMarkdown != currentNote.markdown
        if isModified, appSettings.autoSave { scheduleSave() }
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            _ = self?.saveCurrentNote()
        }
    }

    private func scheduleIndexSynchronization() {
        guard let metadataIndex else { return }
        indexingTask?.cancel()
        indexStatus = VaultIndexStatus(phase: .indexing, completed: 0, total: notes.count, message: text("updatingIndex"))
        let store = self
        indexingTask = Task {
            do {
                let result = try await metadataIndex.synchronize { completed, total in
                    DispatchQueue.main.async {
                        store.indexStatus = VaultIndexStatus(
                            phase: .indexing,
                            completed: completed,
                            total: total,
                            message: store.format("indexingProgress", completed, total)
                        )
                    }
                }
                await MainActor.run {
                    store.indexStatus = VaultIndexStatus(
                        phase: .ready,
                        completed: result.indexed + result.unchanged,
                        total: result.indexed + result.unchanged,
                        message: store.text("indexUpToDate")
                    )
                    store.scheduleSearch()
                    store.refreshIndexedContext()
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    store.indexStatus = VaultIndexStatus(phase: .failed, message: error.localizedDescription)
                }
            }
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let searchIndex else {
            searchResults = []
            return
        }
        searchResults = []
        let store = self
        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                let results = try await searchIndex.search(query)
                try Task.checkCancellation()
                await MainActor.run { store.searchResults = results }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { store.present(error) }
            }
        }
    }

    private func refreshIndexedContext() {
        guard let path = selectedNotePath, let metadataIndex else {
            indexedHeadings = []
            indexedBacklinks = []
            indexedOutgoingLinks = []
            return
        }
        let store = self
        Task {
            do {
                async let headings = metadataIndex.headings(in: path)
                async let outgoing = metadataIndex.outgoingLinks(from: path)
                let targets = [path.deletingPathExtension, path.value, path.value.replacingOccurrences(of: ".md", with: "")]
                async let backlinks = metadataIndex.backlinks(to: targets)
                let values = try await (headings, outgoing, backlinks)
                await MainActor.run {
                    guard store.selectedNotePath == path else { return }
                    store.indexedHeadings = values.0
                    store.indexedOutgoingLinks = values.1
                    store.indexedBacklinks = values.2
                }
            } catch {
                await MainActor.run { store.present(error) }
            }
        }
    }

    private func findItem(_ path: NotePath, in items: [VaultItem]) -> VaultItem? {
        for item in items {
            if item.path == path { return item }
            if let match = findItem(path, in: item.children) { return match }
        }
        return nil
    }

    private func present(_ error: Error) {
        alert = VaultAlert(title: "NotesApp", message: error.localizedDescription)
    }
}
