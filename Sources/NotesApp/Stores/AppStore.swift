import Combine
import Foundation
import NotesCore

enum LibrarySelection: Hashable {
    case all
    case trash
    case tag(Int64)
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

final class AppStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var tags: [Tag] = []
    @Published private(set) var librarySelection: LibrarySelection = .all
    @Published private(set) var selectedNoteID: Int64?
    @Published private(set) var currentNote: Note?
    @Published var draftTitle = "" {
        didSet { draftDidChange() }
    }
    @Published var draftContent = "" {
        didSet { draftDidChange() }
    }
    @Published private(set) var isModified = false
    @Published var searchText = "" {
        didSet { scheduleSearch() }
    }
    @Published private(set) var sorting: NoteSorting = .updatedDescending
    @Published private(set) var settings = AppSettings()
    @Published private(set) var storageDirectory = FileManager.default.temporaryDirectory
    @Published private(set) var activeCount = 0
    @Published private(set) var trashCount = 0
    @Published var alert: AppAlert?

    private let storageManager: StorageManager
    private var database: DatabaseService?
    private var settingsService: SettingsService?
    private var autoSaveTimer: Timer?
    private var searchTimer: Timer?
    private var isLoadingDraft = false

    init(storageManager: StorageManager = .shared) {
        self.storageManager = storageManager
        openInitialStorage()
    }

    deinit {
        autoSaveTimer?.invalidate()
        searchTimer?.invalidate()
    }

    func text(_ key: String) -> String {
        L10n.text(key, language: settings.language)
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }

    func changeLibrarySelection(to selection: LibrarySelection) {
        guard selection != librarySelection else { return }
        guard saveCurrentNote() else { return }
        librarySelection = selection
        reloadNotes()
        if let selectedNoteID, !notes.contains(where: { $0.id == selectedNoteID }) {
            clearSelection()
        }
    }

    func selectNote(_ noteID: Int64?) {
        guard noteID != selectedNoteID else { return }
        guard saveCurrentNote() else { return }
        selectedNoteID = noteID
        loadSelectedNote()
    }

    func createNote() {
        guard saveCurrentNote(), let database else { return }
        do {
            let note = try database.createNote(title: text("newNote"))
            librarySelection = .all
            searchText = ""
            reloadNotes()
            selectedNoteID = note.id
            loadSelectedNote()
        } catch {
            present(error)
        }
    }

    @discardableResult
    func saveCurrentNote() -> Bool {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        guard isModified, let currentNote, let database else { return true }

        do {
            let updated = try database.updateNote(
                currentNote,
                title: draftTitle,
                content: draftContent
            )
            self.currentNote = updated
            isLoadingDraft = true
            draftTitle = updated.title
            draftContent = updated.content
            isLoadingDraft = false
            isModified = false
            reloadNotes()
            return true
        } catch {
            present(error)
            return false
        }
    }

    func moveToTrashOrDelete(_ note: Note) {
        if note.id == currentNote?.id, !saveCurrentNote() {
            return
        }
        guard let database else { return }
        do {
            if note.isDeleted {
                _ = try database.deletePermanently(noteID: note.id)
            } else {
                _ = try database.moveToTrash(noteID: note.id)
            }
            if note.id == selectedNoteID {
                clearSelection()
            }
            reloadNotesAndTags()
        } catch {
            present(error)
        }
    }

    func restore(_ note: Note) {
        guard let database else { return }
        do {
            _ = try database.restore(noteID: note.id)
            if note.id == selectedNoteID {
                clearSelection()
            }
            reloadNotes()
        } catch {
            present(error)
        }
    }

    func togglePinned(_ note: Note) {
        if note.id == currentNote?.id, !saveCurrentNote() {
            return
        }
        guard let database else { return }
        do {
            _ = try database.setPinned(noteID: note.id, isPinned: !note.isPinned)
            reloadNotes()
            if note.id == selectedNoteID {
                loadSelectedNote()
            }
        } catch {
            present(error)
        }
    }

    func setSorting(_ value: NoteSorting) {
        guard sorting != value else { return }
        sorting = value
        reloadNotes()
    }

    func createTag(name: String, colorHex: String) {
        guard let database else { return }
        do {
            _ = try database.createTag(name: name, colorHex: colorHex)
            reloadNotesAndTags()
        } catch {
            present(error)
        }
    }

    func updateTagColor(_ tag: Tag, colorHex: String) {
        guard let database else { return }
        do {
            _ = try database.updateTagColor(tagID: tag.id, colorHex: colorHex)
            reloadNotesAndTags()
            if selectedNoteID != nil {
                loadSelectedNote()
            }
        } catch {
            present(error)
        }
    }

    func deleteTag(_ tag: Tag) {
        guard let database else { return }
        do {
            _ = try database.deleteTag(tagID: tag.id)
            if librarySelection == .tag(tag.id) {
                librarySelection = .all
            }
            reloadNotesAndTags()
            if selectedNoteID != nil {
                loadSelectedNote()
            }
        } catch {
            present(error)
        }
    }

    func addTagToCurrentNote(_ tag: Tag) {
        guard saveCurrentNote(), let noteID = selectedNoteID, let database else { return }
        do {
            try database.addTag(tag.id, toNote: noteID)
            reloadNotesAndTags()
            loadSelectedNote()
        } catch {
            present(error)
        }
    }

    func removeTagFromCurrentNote(_ tag: Tag) {
        guard saveCurrentNote(), let noteID = selectedNoteID, let database else { return }
        do {
            try database.removeTag(tag.id, fromNote: noteID)
            reloadNotesAndTags()
            loadSelectedNote()
        } catch {
            present(error)
        }
    }

    func linkableNotes() -> [Note] {
        guard let database else { return [] }
        do {
            return try database
                .fetchNotes(sorting: .titleAscending)
                .filter { $0.id != selectedNoteID }
        } catch {
            present(error)
            return []
        }
    }

    func openInternalLink(title: String) {
        guard let database else { return }
        do {
            let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = try database.fetchNotes().first {
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .compare(normalized, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            guard let candidate else {
                alert = AppAlert(title: text("internalLink"), message: format("linkNotFound", normalized))
                return
            }
            guard saveCurrentNote() else { return }
            librarySelection = .all
            searchText = ""
            reloadNotes()
            selectedNoteID = candidate.id
            loadSelectedNote()
        } catch {
            present(error)
        }
    }

    func applySettings(_ value: AppSettings) {
        do {
            try settingsService?.save(value)
            settings = value
            sorting = value.defaultSorting
            reloadNotes()
            if value.autoSave, isModified {
                scheduleAutoSave()
            } else if !value.autoSave {
                autoSaveTimer?.invalidate()
            }
        } catch {
            present(error)
        }
    }

    func chooseStorageDirectory(_ directory: URL) {
        guard saveCurrentNote() else { return }
        do {
            let newDatabase = try DatabaseService(directory: directory)
            let newSettingsService = SettingsService(directory: directory)
            let newSettings = newSettingsService.load()
            try storageManager.setCurrentDirectory(directory)

            database = newDatabase
            settingsService = newSettingsService
            settings = newSettings
            sorting = newSettings.defaultSorting
            storageDirectory = directory.standardizedFileURL
            librarySelection = .all
            searchText = ""
            clearSelection()
            reloadNotesAndTags()
        } catch {
            present(error)
        }
    }

    func refresh() {
        reloadNotesAndTags()
        if selectedNoteID != nil {
            loadSelectedNote()
        }
    }

    func sortingTitle(_ value: NoteSorting) -> String {
        switch value {
        case .updatedDescending: return text("recentFirst")
        case .updatedAscending: return text("oldestFirst")
        case .titleAscending: return text("titleAscending")
        case .titleDescending: return text("titleDescending")
        case .createdDescending: return text("createdNewest")
        case .createdAscending: return text("createdOldest")
        }
    }

    private func openInitialStorage() {
        do {
            let directory = try storageManager.currentDirectory()
            let database = try DatabaseService(directory: directory)
            let settingsService = SettingsService(directory: directory)
            let settings = settingsService.load()

            storageDirectory = directory
            self.database = database
            self.settingsService = settingsService
            self.settings = settings
            sorting = settings.defaultSorting
            reloadNotesAndTags()
        } catch {
            alert = AppAlert(title: L10n.text("databaseError", language: .russian), message: error.localizedDescription)
        }
    }

    private func reloadNotesAndTags() {
        reloadTags()
        reloadNotes()
    }

    private func reloadTags() {
        guard let database else { return }
        do {
            tags = try database.fetchTags()
        } catch {
            present(error)
        }
    }

    private func reloadNotes() {
        guard let database else { return }
        do {
            let loaded: [Note]
            switch librarySelection {
            case .all:
                loaded = try database.fetchNotes(sorting: sorting)
            case .trash:
                loaded = try database.fetchNotes(includeDeleted: true, onlyDeleted: true, sorting: sorting)
            case .tag(let tagID):
                loaded = try database.fetchNotes(sorting: sorting, tagID: tagID)
            }

            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty {
                notes = loaded
            } else {
                notes = loaded.filter { note in
                    note.title.localizedCaseInsensitiveContains(query)
                        || RichTextCodec.plainText(from: note.content).localizedCaseInsensitiveContains(query)
                        || note.tags.contains { $0.name.localizedCaseInsensitiveContains(query) }
                }
            }

            activeCount = try database.fetchNotes().count
            trashCount = try database.fetchNotes(includeDeleted: true, onlyDeleted: true).count
        } catch {
            present(error)
        }
    }

    private func loadSelectedNote() {
        autoSaveTimer?.invalidate()
        guard let selectedNoteID, let database else {
            clearDraft()
            return
        }

        do {
            guard let note = try database.fetchNote(id: selectedNoteID) else {
                clearSelection()
                return
            }
            currentNote = note
            isLoadingDraft = true
            draftTitle = note.title
            draftContent = note.content
            isLoadingDraft = false
            isModified = false
        } catch {
            present(error)
            clearSelection()
        }
    }

    private func clearSelection() {
        selectedNoteID = nil
        clearDraft()
    }

    private func clearDraft() {
        isLoadingDraft = true
        currentNote = nil
        draftTitle = ""
        draftContent = ""
        isLoadingDraft = false
        isModified = false
        autoSaveTimer?.invalidate()
    }

    private func draftDidChange() {
        guard !isLoadingDraft, let currentNote else { return }
        isModified = draftTitle != currentNote.title || draftContent != currentNote.content
        if isModified, settings.autoSave {
            scheduleAutoSave()
        }
    }

    private func scheduleAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            _ = self?.saveCurrentNote()
        }
    }

    private func scheduleSearch() {
        searchTimer?.invalidate()
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.reloadNotes()
        }
    }

    private func present(_ error: Error) {
        alert = AppAlert(title: text("error"), message: error.localizedDescription)
    }
}
