import Foundation

public struct IndexingResult: Equatable {
    public let indexed: Int
    public let removed: Int
    public let unchanged: Int

    public init(indexed: Int, removed: Int, unchanged: Int) {
        self.indexed = indexed
        self.removed = removed
        self.unchanged = unchanged
    }
}

public struct IndexedHeading: Equatable {
    public let path: NotePath
    public let level: Int
    public let text: String
    public let blockID: String?
}

public struct IndexedBacklink: Equatable {
    public let sourcePath: NotePath
    public let destination: String
    public let context: String
    public let heading: String?
    public let blockID: String?
}

public enum MetadataIndexError: LocalizedError {
    case invalidStoredPath(String)

    public var errorDescription: String? {
        switch self {
        case .invalidStoredPath(let path): return "The metadata index contains an invalid vault path: \(path)"
        }
    }
}

/// A rebuildable SQLite cache. All database work is actor-isolated and never owns note data.
public actor MetadataIndex {
    public let vaultURL: URL
    public let databaseURL: URL

    private let connection: SQLiteConnection
    private let parser = MarkdownParser()
    private let renderer = MarkdownRenderer()
    private let extractor = MarkdownLinkExtractor()

    public init(vaultURL: URL) throws {
        self.vaultURL = vaultURL.standardizedFileURL
        let metadataURL = self.vaultURL.appendingPathComponent(".notesapp", isDirectory: true)
        try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
        databaseURL = metadataURL.appendingPathComponent("index.sqlite")
        do {
            let opened = try SQLiteConnection(url: databaseURL)
            try Self.createSchema(opened)
            connection = opened
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let quarantine = metadataURL.appendingPathComponent("index.corrupt-\(stamp).sqlite")
            if FileManager.default.fileExists(atPath: databaseURL.path) {
                try? FileManager.default.moveItem(at: databaseURL, to: quarantine)
            }
            for suffix in ["-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: databaseURL.path + suffix)
                if FileManager.default.fileExists(atPath: sidecar.path) { try? FileManager.default.removeItem(at: sidecar) }
            }
            let rebuilt = try SQLiteConnection(url: databaseURL)
            try Self.createSchema(rebuilt)
            connection = rebuilt
        }
    }

    public func synchronize(progress: (@Sendable (Int, Int) -> Void)? = nil) throws -> IndexingResult {
        let service = try VaultFileService(rootURL: vaultURL)
        let snapshot = try service.snapshot()
        let existing = try indexedFileSignatures()
        let currentPaths = Set(snapshot.notes.map(\.path.value))
        let removedPaths = Set(existing.keys).subtracting(currentPaths)
        var indexed = 0
        var unchanged = 0

        for (offset, metadata) in snapshot.notes.enumerated() {
            try Task.checkCancellation()
            let signature = FileSignature(modifiedAt: metadata.modifiedAt.timeIntervalSince1970, fileSize: metadata.fileSize)
            if existing[metadata.path.value] == signature {
                unchanged += 1
            } else {
                try index(service.readNote(at: metadata.path))
                indexed += 1
            }
            progress?(offset + 1, snapshot.notes.count)
        }

        if !removedPaths.isEmpty {
            try connection.transaction {
                for path in removedPaths { try delete(path: path) }
            }
        }
        return IndexingResult(indexed: indexed, removed: removedPaths.count, unchanged: unchanged)
    }

    public func rebuild(progress: (@Sendable (Int, Int) -> Void)? = nil) throws -> IndexingResult {
        try connection.transaction {
            try connection.execute("DELETE FROM files; DELETE FROM headings; DELETE FROM blocks; DELETE FROM links; DELETE FROM properties; DELETE FROM tags; DELETE FROM aliases; DELETE FROM tasks; DELETE FROM attachment_refs; DELETE FROM notes_fts;")
        }
        return try synchronize(progress: progress)
    }

    public func removeCache() throws {
        try connection.execute("DELETE FROM files; DELETE FROM headings; DELETE FROM blocks; DELETE FROM links; DELETE FROM properties; DELETE FROM tags; DELETE FROM aliases; DELETE FROM tasks; DELETE FROM attachment_refs; DELETE FROM notes_fts;")
    }

    public func outgoingLinks(from path: NotePath) throws -> [MarkdownLinkReference] {
        let statement = try connection.prepare(
            "SELECT kind, destination, label, heading, block_id FROM links WHERE source_path = ? ORDER BY rowid;"
        )
        try statement.bind(path.value, at: 1)
        var result: [MarkdownLinkReference] = []
        while try statement.step() {
            guard let kind = MarkdownLinkKind(rawValue: statement.string(at: 0)) else { continue }
            result.append(MarkdownLinkReference(
                kind: kind,
                destination: statement.string(at: 1),
                label: statement.optionalString(at: 2),
                heading: statement.optionalString(at: 3),
                blockID: statement.optionalString(at: 4),
                range: MarkdownSourceRange(0, 0)
            ))
        }
        return result
    }

    public func backlinks(to destinations: [String]) throws -> [IndexedBacklink] {
        guard !destinations.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: destinations.count).joined(separator: ",")
        let statement = try connection.prepare(
            "SELECT source_path, destination, context, heading, block_id FROM links WHERE destination COLLATE NOCASE IN (\(placeholders)) ORDER BY source_path;"
        )
        for (offset, destination) in destinations.enumerated() {
            try statement.bind(destination, at: Int32(offset + 1))
        }
        var result: [IndexedBacklink] = []
        while try statement.step() {
            let rawPath = statement.string(at: 0)
            guard let path = try? NotePath(rawPath) else { throw MetadataIndexError.invalidStoredPath(rawPath) }
            result.append(IndexedBacklink(
                sourcePath: path,
                destination: statement.string(at: 1),
                context: statement.string(at: 2),
                heading: statement.optionalString(at: 3),
                blockID: statement.optionalString(at: 4)
            ))
        }
        return result
    }

    public func headings(in path: NotePath) throws -> [IndexedHeading] {
        let statement = try connection.prepare(
            "SELECT level, text, block_id FROM headings WHERE path = ? ORDER BY position;"
        )
        try statement.bind(path.value, at: 1)
        var result: [IndexedHeading] = []
        while try statement.step() {
            result.append(IndexedHeading(
                path: path,
                level: Int(statement.int64(at: 0)),
                text: statement.string(at: 1),
                blockID: statement.optionalString(at: 2)
            ))
        }
        return result
    }

    private func index(_ note: VaultNote) throws {
        let document = parser.parse(note.markdown)
        let plainBody = renderer.plainText(document)
        let headings = collectHeadings(document.blocks)
        let links = extractor.extract(from: document)
        let properties = document.frontmatter?.properties ?? [:]
        let tags = stringArray(properties["tags"])
        let aliases = stringArray(properties["aliases"])
        let title = note.title
        let modified = String(note.revision.modifiedAt.timeIntervalSince1970)

        try connection.transaction {
            try delete(path: note.path.value)

            let file = try connection.prepare(
                "INSERT INTO files(path, title, modified_at, file_size, content_hash) VALUES (?, ?, ?, ?, ?);"
            )
            try file.bind(note.path.value, at: 1)
            try file.bind(title, at: 2)
            try file.bind(modified, at: 3)
            try file.bind(Int64(note.revision.byteCount), at: 4)
            try file.bind(String(note.revision.fingerprint), at: 5)
            try file.step()

            for (position, heading) in headings.enumerated() {
                let statement = try connection.prepare(
                    "INSERT INTO headings(path, position, level, text, block_id) VALUES (?, ?, ?, ?, ?);"
                )
                try statement.bind(note.path.value, at: 1)
                try statement.bind(Int64(position), at: 2)
                try statement.bind(Int64(heading.level), at: 3)
                try statement.bind(heading.text, at: 4)
                try statement.bind(heading.blockID, at: 5)
                try statement.step()
            }

            for block in collectBlocks(document.blocks) {
                guard let blockID = block.blockID else { continue }
                let statement = try connection.prepare("INSERT INTO blocks(path, block_id, text) VALUES (?, ?, ?);")
                try statement.bind(note.path.value, at: 1)
                try statement.bind(blockID, at: 2)
                try statement.bind(renderer.plainText(MarkdownDocument(frontmatter: nil, blocks: [block], source: "")), at: 3)
                try statement.step()
            }

            for link in links {
                let statement = try connection.prepare(
                    "INSERT INTO links(source_path, kind, destination, label, heading, block_id, context) VALUES (?, ?, ?, ?, ?, ?, ?);"
                )
                try statement.bind(note.path.value, at: 1)
                try statement.bind(link.kind.rawValue, at: 2)
                try statement.bind(link.destination, at: 3)
                try statement.bind(link.label, at: 4)
                try statement.bind(link.heading, at: 5)
                try statement.bind(link.blockID, at: 6)
                try statement.bind(context(for: link, in: note.markdown), at: 7)
                try statement.step()
                if link.kind == .image || link.kind == .embed {
                    let attachment = try connection.prepare(
                        "INSERT INTO attachment_refs(source_path, target) VALUES (?, ?);"
                    )
                    try attachment.bind(note.path.value, at: 1)
                    try attachment.bind(link.destination, at: 2)
                    try attachment.step()
                }
            }

            for key in document.frontmatter?.keyOrder ?? properties.keys.sorted() {
                guard let value = properties[key] else { continue }
                let statement = try connection.prepare(
                    "INSERT INTO properties(path, key, type, value) VALUES (?, ?, ?, ?);"
                )
                try statement.bind(note.path.value, at: 1)
                try statement.bind(key, at: 2)
                try statement.bind(yamlType(value), at: 3)
                try statement.bind(yamlText(value), at: 4)
                try statement.step()
            }
            for tag in tags {
                let statement = try connection.prepare("INSERT INTO tags(path, tag) VALUES (?, ?);")
                try statement.bind(note.path.value, at: 1)
                try statement.bind(tag, at: 2)
                try statement.step()
            }
            for alias in aliases {
                let statement = try connection.prepare("INSERT INTO aliases(path, alias) VALUES (?, ?);")
                try statement.bind(note.path.value, at: 1)
                try statement.bind(alias, at: 2)
                try statement.step()
            }
            for (position, task) in collectTasks(document.blocks).enumerated() {
                let statement = try connection.prepare("INSERT INTO tasks(path, position, state, text) VALUES (?, ?, ?, ?);")
                try statement.bind(note.path.value, at: 1)
                try statement.bind(Int64(position), at: 2)
                try statement.bind(task.state.rawValue, at: 3)
                try statement.bind(task.text, at: 4)
                try statement.step()
            }

            let fts = try connection.prepare(
                "INSERT INTO notes_fts(path, title, body, headings, tags, properties) VALUES (?, ?, ?, ?, ?, ?);"
            )
            try fts.bind(note.path.value, at: 1)
            try fts.bind(title, at: 2)
            try fts.bind(plainBody, at: 3)
            try fts.bind(headings.map(\.text).joined(separator: " "), at: 4)
            try fts.bind(tags.joined(separator: " "), at: 5)
            try fts.bind(properties.map { "\($0.key):\(yamlText($0.value))" }.joined(separator: " "), at: 6)
            try fts.step()
        }
    }

    private func delete(path: String) throws {
        for table in ["files", "headings", "blocks", "links", "properties", "tags", "aliases", "tasks", "attachment_refs", "notes_fts"] {
            let statement = try connection.prepare("DELETE FROM \(table) WHERE \(table == "links" || table == "attachment_refs" ? "source_path" : "path") = ?;")
            try statement.bind(path, at: 1)
            try statement.step()
        }
    }

    private func indexedFileSignatures() throws -> [String: FileSignature] {
        let statement = try connection.prepare("SELECT path, modified_at, file_size FROM files;")
        var result: [String: FileSignature] = [:]
        while try statement.step() {
            result[statement.string(at: 0)] = FileSignature(
                modifiedAt: Double(statement.string(at: 1)) ?? 0,
                fileSize: statement.int64(at: 2)
            )
        }
        return result
    }

    private func collectHeadings(_ blocks: [MarkdownBlock]) -> [(level: Int, text: String, blockID: String?)] {
        blocks.flatMap { block -> [(Int, String, String?)] in
            switch block.kind {
            case .heading(let level, _):
                return [(level, renderer.plainText(MarkdownDocument(frontmatter: nil, blocks: [block], source: "")), block.blockID)]
            case .blockquote(let children): return collectHeadings(children)
            case .callout(let callout): return collectHeadings(callout.blocks)
            case .list(let list): return list.items.flatMap { collectHeadings($0.blocks) }
            default: return []
            }
        }
    }

    private func collectBlocks(_ blocks: [MarkdownBlock]) -> [MarkdownBlock] {
        blocks.flatMap { block -> [MarkdownBlock] in
            var result = [block]
            switch block.kind {
            case .blockquote(let children): result += collectBlocks(children)
            case .callout(let callout): result += collectBlocks(callout.blocks)
            case .list(let list): result += list.items.flatMap { collectBlocks($0.blocks) }
            case .footnoteDefinition(_, let children): result += collectBlocks(children)
            default: break
            }
            return result
        }
    }

    private func collectTasks(_ blocks: [MarkdownBlock]) -> [(state: MarkdownTaskState, text: String)] {
        blocks.flatMap { block -> [(MarkdownTaskState, String)] in
            switch block.kind {
            case .list(let list):
                return list.items.flatMap { item -> [(MarkdownTaskState, String)] in
                    var result: [(MarkdownTaskState, String)] = []
                    if let state = item.task {
                        let text = item.blocks.map {
                            renderer.plainText(MarkdownDocument(frontmatter: nil, blocks: [$0], source: ""))
                        }.joined(separator: " ")
                        result.append((state, text))
                    }
                    result += collectTasks(item.blocks)
                    return result
                }
            case .blockquote(let children): return collectTasks(children)
            case .callout(let callout): return collectTasks(callout.blocks)
            default: return []
            }
        }
    }

    private func context(for link: MarkdownLinkReference, in markdown: String) -> String {
        let source = markdown as NSString
        let location = min(max(0, link.range.lowerBound), source.length)
        let line = source.lineRange(for: NSRange(location: location, length: 0))
        return source.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stringArray(_ value: YAMLValue?) -> [String] {
        switch value {
        case .string(let string)?: return [string]
        case .array(let values)?: return values.compactMap { if case .string(let value) = $0 { return value }; return nil }
        default: return []
        }
    }

    private func yamlType(_ value: YAMLValue) -> String {
        switch value {
        case .string: return "text"
        case .number: return "number"
        case .bool: return "checkbox"
        case .null: return "null"
        case .array: return "list"
        case .object: return "object"
        }
    }

    private func yamlText(_ value: YAMLValue) -> String {
        switch value {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return ""
        case .array(let values): return values.map(yamlText).joined(separator: ", ")
        case .object(let values): return values.map { "\($0.key): \(yamlText($0.value))" }.joined(separator: ", ")
        }
    }

    private static func createSchema(_ connection: SQLiteConnection) throws {
        try connection.execute(
            """
            PRAGMA user_version = 1;
            CREATE TABLE IF NOT EXISTS files (
                path TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                modified_at TEXT NOT NULL,
                file_size INTEGER NOT NULL,
                content_hash TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS headings (path TEXT NOT NULL, position INTEGER NOT NULL, level INTEGER NOT NULL, text TEXT NOT NULL, block_id TEXT);
            CREATE INDEX IF NOT EXISTS idx_headings_path ON headings(path);
            CREATE TABLE IF NOT EXISTS blocks (path TEXT NOT NULL, block_id TEXT NOT NULL, text TEXT NOT NULL);
            CREATE UNIQUE INDEX IF NOT EXISTS idx_blocks_identity ON blocks(path, block_id);
            CREATE TABLE IF NOT EXISTS links (source_path TEXT NOT NULL, kind TEXT NOT NULL, destination TEXT NOT NULL, label TEXT, heading TEXT, block_id TEXT, context TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS idx_links_source ON links(source_path);
            CREATE INDEX IF NOT EXISTS idx_links_destination ON links(destination COLLATE NOCASE);
            CREATE TABLE IF NOT EXISTS properties (path TEXT NOT NULL, key TEXT NOT NULL, type TEXT NOT NULL, value TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS idx_properties_key ON properties(key, value);
            CREATE TABLE IF NOT EXISTS tags (path TEXT NOT NULL, tag TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS idx_tags_tag ON tags(tag COLLATE NOCASE);
            CREATE TABLE IF NOT EXISTS aliases (path TEXT NOT NULL, alias TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS idx_aliases_alias ON aliases(alias COLLATE NOCASE);
            CREATE TABLE IF NOT EXISTS tasks (path TEXT NOT NULL, position INTEGER NOT NULL, state TEXT NOT NULL, text TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS idx_tasks_state ON tasks(state, path);
            CREATE TABLE IF NOT EXISTS attachment_refs (source_path TEXT NOT NULL, target TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS idx_attachment_target ON attachment_refs(target);
            CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
                path UNINDEXED, title, body, headings, tags, properties,
                tokenize = 'unicode61 remove_diacritics 2'
            );
            """
        )
    }
}

private struct FileSignature: Equatable {
    let modifiedAt: TimeInterval
    let fileSize: Int64
}
