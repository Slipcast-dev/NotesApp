import Foundation

public final class DatabaseService {
    public let directory: URL
    public let databaseURL: URL

    private let connection: SQLiteConnection
    private let markdownStore: MarkdownNoteStore

    public init(directory: URL) throws {
        self.directory = directory
        databaseURL = directory.appendingPathComponent("notes.db")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        connection = try SQLiteConnection(url: databaseURL)
        markdownStore = MarkdownNoteStore(directory: directory)
        try initializeSchema()
        try materializeMarkdownFiles()
    }

    public func fetchNotes(
        includeDeleted: Bool = false,
        onlyDeleted: Bool = false,
        searchText: String? = nil,
        sorting: NoteSorting = .updatedDescending,
        tagID: Int64? = nil
    ) throws -> [Note] {
        var predicates: [String] = []
        if onlyDeleted {
            predicates.append("n.IsDeleted = 1")
        } else if !includeDeleted {
            predicates.append("n.IsDeleted = 0")
        }
        if tagID != nil {
            predicates.append("EXISTS (SELECT 1 FROM NoteTags nt WHERE nt.NoteId = n.Id AND nt.TagId = ?)")
        }

        let whereClause = predicates.isEmpty ? "" : "WHERE " + predicates.joined(separator: " AND ")
        let orderClause: String
        switch sorting {
        case .titleAscending:
            orderClause = "n.Title COLLATE NOCASE ASC"
        case .titleDescending:
            orderClause = "n.Title COLLATE NOCASE DESC"
        case .createdAscending:
            orderClause = "n.CreatedAt ASC"
        case .createdDescending:
            orderClause = "n.CreatedAt DESC"
        case .updatedAscending:
            orderClause = "n.UpdatedAt ASC"
        case .updatedDescending:
            orderClause = "n.UpdatedAt DESC"
        }

        let statement = try connection.prepare(
            """
            SELECT n.Id, n.Title, n.Content, n.MarkdownFileName,
                   n.CreatedAt, n.UpdatedAt, n.IsPinned, n.IsDeleted
            FROM Notes n
            \(whereClause)
            ORDER BY n.IsPinned DESC, \(orderClause);
            """
        )
        if let tagID {
            try statement.bind(tagID, at: 1)
        }

        var notes: [Note] = []
        while try statement.step() {
            let id = statement.int64(at: 0)
            let note = Note(
                id: id,
                title: statement.string(at: 1),
                content: statement.string(at: 2),
                markdownFileName: statement.optionalString(at: 3),
                createdAt: DatabaseDateCoding.date(from: statement.string(at: 4)),
                updatedAt: DatabaseDateCoding.date(from: statement.string(at: 5)),
                isPinned: statement.bool(at: 6),
                isDeleted: statement.bool(at: 7),
                tags: try fetchTags(forNoteID: id)
            )
            notes.append(markdownStore.read(into: note))
        }

        guard let searchText = searchText?.trimmingCharacters(in: .whitespacesAndNewlines), !searchText.isEmpty else {
            return notes
        }

        return notes.filter { note in
            note.title.localizedCaseInsensitiveContains(searchText)
                || note.content.localizedCaseInsensitiveContains(searchText)
                || note.tags.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    public func fetchNote(id: Int64) throws -> Note? {
        try fetchNotes(includeDeleted: true).first { $0.id == id }
    }

    public func createNote(title: String, content: String = "") throws -> Note {
        try connection.transaction {
            let now = Date()
            let insert = try connection.prepare(
                """
                INSERT INTO Notes (Title, Content, MarkdownFileName, CreatedAt, UpdatedAt, IsPinned, IsDeleted)
                VALUES (?, ?, NULL, ?, ?, 0, 0);
                """
            )
            try insert.bind(normalizedTitle(title), at: 1)
            try insert.bind(content, at: 2)
            try insert.bind(DatabaseDateCoding.string(from: now), at: 3)
            try insert.bind(DatabaseDateCoding.string(from: now), at: 4)
            try insert.step()

            let id = connection.lastInsertRowID
            let fileName = markdownStore.fileName(for: id)
            let update = try connection.prepare("UPDATE Notes SET MarkdownFileName = ? WHERE Id = ?;")
            try update.bind(fileName, at: 1)
            try update.bind(id, at: 2)
            try update.step()

            let note = Note(
                id: id,
                title: normalizedTitle(title),
                content: content,
                markdownFileName: fileName,
                createdAt: now,
                updatedAt: now,
                isPinned: false,
                isDeleted: false
            )
            try markdownStore.write(note)
            return note
        }
    }

    @discardableResult
    public func updateNote(_ note: Note, title: String, content: String) throws -> Note {
        var updated = note
        updated.title = normalizedTitle(title)
        updated.content = content
        updated.updatedAt = Date()
        updated.markdownFileName = updated.markdownFileName ?? markdownStore.fileName(for: note.id)

        return try connection.transaction {
            try markdownStore.write(updated)
            let statement = try connection.prepare(
                """
                UPDATE Notes
                SET Title = ?, Content = ?, MarkdownFileName = ?, UpdatedAt = ?, IsPinned = ?
                WHERE Id = ?;
                """
            )
            try statement.bind(updated.title, at: 1)
            try statement.bind(updated.content, at: 2)
            try statement.bind(updated.markdownFileName, at: 3)
            try statement.bind(DatabaseDateCoding.string(from: updated.updatedAt), at: 4)
            try statement.bind(updated.isPinned, at: 5)
            try statement.bind(updated.id, at: 6)
            try statement.step()
            return updated
        }
    }

    @discardableResult
    public func setPinned(noteID: Int64, isPinned: Bool) throws -> Bool {
        let statement = try connection.prepare("UPDATE Notes SET IsPinned = ?, UpdatedAt = ? WHERE Id = ?;")
        try statement.bind(isPinned, at: 1)
        try statement.bind(DatabaseDateCoding.string(from: Date()), at: 2)
        try statement.bind(noteID, at: 3)
        try statement.step()
        return connection.changes > 0
    }

    @discardableResult
    public func moveToTrash(noteID: Int64) throws -> Bool {
        let statement = try connection.prepare("UPDATE Notes SET IsDeleted = 1, UpdatedAt = ? WHERE Id = ?;")
        try statement.bind(DatabaseDateCoding.string(from: Date()), at: 1)
        try statement.bind(noteID, at: 2)
        try statement.step()
        return connection.changes > 0
    }

    @discardableResult
    public func restore(noteID: Int64) throws -> Bool {
        let statement = try connection.prepare("UPDATE Notes SET IsDeleted = 0, UpdatedAt = ? WHERE Id = ?;")
        try statement.bind(DatabaseDateCoding.string(from: Date()), at: 1)
        try statement.bind(noteID, at: 2)
        try statement.step()
        return connection.changes > 0
    }

    @discardableResult
    public func deletePermanently(noteID: Int64) throws -> Bool {
        let note = try fetchNote(id: noteID)
        let deleted = try connection.transaction {
            let statement = try connection.prepare("DELETE FROM Notes WHERE Id = ?;")
            try statement.bind(noteID, at: 1)
            try statement.step()
            return connection.changes > 0
        }
        if deleted, let note {
            try? FileManager.default.removeItem(at: markdownStore.fileURL(for: note))
        }
        return deleted
    }

    public func fetchTags() throws -> [Tag] {
        let statement = try connection.prepare("SELECT Id, Name, ColorHex FROM Tags ORDER BY Name COLLATE NOCASE;")
        var tags: [Tag] = []
        while try statement.step() {
            tags.append(Tag(
                id: statement.int64(at: 0),
                name: statement.string(at: 1),
                colorHex: HexColor.normalize(statement.string(at: 2))
            ))
        }
        return tags
    }

    public func createTag(name: String, colorHex: String?) throws -> Tag {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw NotesDatabaseError(operation: "Create tag", message: "Tag name cannot be empty")
        }

        if let existing = try findTag(name: normalizedName) {
            return existing
        }

        let color = HexColor.normalize(colorHex)
        let statement = try connection.prepare("INSERT INTO Tags (Name, ColorHex) VALUES (?, ?);")
        try statement.bind(String(normalizedName.prefix(50)), at: 1)
        try statement.bind(color, at: 2)
        try statement.step()
        return Tag(id: connection.lastInsertRowID, name: String(normalizedName.prefix(50)), colorHex: color)
    }

    @discardableResult
    public func updateTagColor(tagID: Int64, colorHex: String) throws -> Bool {
        let statement = try connection.prepare("UPDATE Tags SET ColorHex = ? WHERE Id = ?;")
        try statement.bind(HexColor.normalize(colorHex), at: 1)
        try statement.bind(tagID, at: 2)
        try statement.step()
        return connection.changes > 0
    }

    @discardableResult
    public func deleteTag(tagID: Int64) throws -> Bool {
        let statement = try connection.prepare("DELETE FROM Tags WHERE Id = ?;")
        try statement.bind(tagID, at: 1)
        try statement.step()
        return connection.changes > 0
    }

    public func addTag(_ tagID: Int64, toNote noteID: Int64) throws {
        let statement = try connection.prepare("INSERT OR IGNORE INTO NoteTags (NoteId, TagId) VALUES (?, ?);")
        try statement.bind(noteID, at: 1)
        try statement.bind(tagID, at: 2)
        try statement.step()
    }

    public func removeTag(_ tagID: Int64, fromNote noteID: Int64) throws {
        let statement = try connection.prepare("DELETE FROM NoteTags WHERE NoteId = ? AND TagId = ?;")
        try statement.bind(noteID, at: 1)
        try statement.bind(tagID, at: 2)
        try statement.step()
    }

    private func initializeSchema() throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS Notes (
                Id INTEGER NOT NULL CONSTRAINT PK_Notes PRIMARY KEY AUTOINCREMENT,
                Title TEXT NOT NULL,
                Content TEXT NOT NULL,
                MarkdownFileName TEXT NULL,
                CreatedAt TEXT NOT NULL,
                UpdatedAt TEXT NOT NULL,
                IsPinned INTEGER NOT NULL,
                IsDeleted INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS Tags (
                Id INTEGER NOT NULL CONSTRAINT PK_Tags PRIMARY KEY AUTOINCREMENT,
                Name TEXT NOT NULL,
                ColorHex TEXT NOT NULL DEFAULT '#4C8DFF'
            );

            CREATE TABLE IF NOT EXISTS NoteTags (
                NoteId INTEGER NOT NULL,
                TagId INTEGER NOT NULL,
                CONSTRAINT PK_NoteTags PRIMARY KEY (NoteId, TagId),
                CONSTRAINT FK_NoteTags_Notes_NoteId FOREIGN KEY (NoteId) REFERENCES Notes (Id) ON DELETE CASCADE,
                CONSTRAINT FK_NoteTags_Tags_TagId FOREIGN KEY (TagId) REFERENCES Tags (Id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS IX_Notes_IsDeleted ON Notes (IsDeleted);
            CREATE INDEX IF NOT EXISTS IX_Notes_CreatedAt ON Notes (CreatedAt);
            CREATE INDEX IF NOT EXISTS IX_Notes_UpdatedAt ON Notes (UpdatedAt);
            CREATE UNIQUE INDEX IF NOT EXISTS IX_Tags_Name ON Tags (Name);
            CREATE INDEX IF NOT EXISTS IX_NoteTags_TagId ON NoteTags (TagId);
            """
        )

        if try !hasColumn("ColorHex", in: "Tags") {
            try connection.execute("ALTER TABLE Tags ADD COLUMN ColorHex TEXT NOT NULL DEFAULT '#4C8DFF';")
        }
        if try !hasColumn("MarkdownFileName", in: "Notes") {
            try connection.execute("ALTER TABLE Notes ADD COLUMN MarkdownFileName TEXT NULL;")
        }
    }

    private func materializeMarkdownFiles() throws {
        let notes = try fetchNotes(includeDeleted: true)
        for var note in notes {
            let url = markdownStore.fileURL(for: note)
            if note.markdownFileName != nil, FileManager.default.fileExists(atPath: url.path) {
                continue
            }

            note.markdownFileName = markdownStore.fileName(for: note.id)
            try markdownStore.write(note)
            let statement = try connection.prepare("UPDATE Notes SET MarkdownFileName = ? WHERE Id = ?;")
            try statement.bind(note.markdownFileName, at: 1)
            try statement.bind(note.id, at: 2)
            try statement.step()
        }
    }

    private func fetchTags(forNoteID noteID: Int64) throws -> [Tag] {
        let statement = try connection.prepare(
            """
            SELECT t.Id, t.Name, t.ColorHex
            FROM Tags t
            INNER JOIN NoteTags nt ON nt.TagId = t.Id
            WHERE nt.NoteId = ?
            ORDER BY t.Name COLLATE NOCASE;
            """
        )
        try statement.bind(noteID, at: 1)
        var tags: [Tag] = []
        while try statement.step() {
            tags.append(Tag(
                id: statement.int64(at: 0),
                name: statement.string(at: 1),
                colorHex: HexColor.normalize(statement.string(at: 2))
            ))
        }
        return tags
    }

    private func findTag(name: String) throws -> Tag? {
        let statement = try connection.prepare(
            "SELECT Id, Name, ColorHex FROM Tags WHERE Name = ? COLLATE NOCASE LIMIT 1;"
        )
        try statement.bind(name, at: 1)
        guard try statement.step() else { return nil }
        return Tag(
            id: statement.int64(at: 0),
            name: statement.string(at: 1),
            colorHex: HexColor.normalize(statement.string(at: 2))
        )
    }

    private func hasColumn(_ column: String, in table: String) throws -> Bool {
        let statement = try connection.prepare("PRAGMA table_info('\(table)');")
        while try statement.step() {
            if statement.string(at: 1) == column {
                return true
            }
        }
        return false
    }

    private func normalizedTitle(_ title: String) -> String {
        let normalized = title
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((normalized.isEmpty ? "Untitled" : normalized).prefix(200))
    }
}
