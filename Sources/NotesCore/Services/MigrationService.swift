import CSQLite
import Foundation

public struct LegacyStoreInfo: Equatable {
    public let databaseURL: URL
    public let noteCount: Int
    public let activeNoteCount: Int
    public let deletedNoteCount: Int
    public let tagCount: Int

    public init(databaseURL: URL, noteCount: Int, activeNoteCount: Int, deletedNoteCount: Int, tagCount: Int) {
        self.databaseURL = databaseURL
        self.noteCount = noteCount
        self.activeNoteCount = activeNoteCount
        self.deletedNoteCount = deletedNoteCount
        self.tagCount = tagCount
    }
}

public enum MigrationItemStatus: String, Codable {
    case planned
    case imported
    case skippedAlreadyImported
    case failed
}

public struct MigrationItemResult: Codable, Identifiable {
    public let legacyID: Int64
    public let title: String
    public let outputPath: String?
    public let status: MigrationItemStatus
    public let warnings: [String]
    public let error: String?

    public var id: Int64 { legacyID }
}

public struct MigrationReport: Codable, Identifiable {
    public let id: String
    public let sourceDatabasePath: String
    public let targetVaultPath: String
    public let generatedAt: Date
    public let dryRun: Bool
    public let backupPath: String?
    public let items: [MigrationItemResult]

    public var importedCount: Int { items.filter { $0.status == .imported }.count }
    public var skippedCount: Int { items.filter { $0.status == .skippedAlreadyImported }.count }
    public var failedCount: Int { items.filter { $0.status == .failed }.count }
}

public struct MigrationUndoReport {
    public let restoredToUndoFolder: [String]
    public let skippedModifiedFiles: [String]

    public init(restoredToUndoFolder: [String], skippedModifiedFiles: [String]) {
        self.restoredToUndoFolder = restoredToUndoFolder
        self.skippedModifiedFiles = skippedModifiedFiles
    }
}

public enum MigrationError: LocalizedError {
    case databaseMissing(URL)
    case unsupportedSchema
    case backupFailed(String)
    case noMigrationManifest
    case sourceAndTargetMustDiffer

    public var errorDescription: String? {
        switch self {
        case .databaseMissing(let url): return "Legacy database not found: \(url.path)"
        case .unsupportedSchema: return "The selected notes.db does not contain the supported Notes/Tags schema."
        case .backupFailed(let message): return "Could not create the pre-migration backup: \(message)"
        case .noMigrationManifest: return "No completed migration manifest was found for this source."
        case .sourceAndTargetMustDiffer: return "Choose a target vault outside the legacy data folder so the original RTF files remain isolated and untouched."
        }
    }
}

public final class MigrationService {
    private let converter: RTFMarkdownConverter
    private let fileManager: FileManager

    public init(converter: RTFMarkdownConverter = RTFMarkdownConverter(), fileManager: FileManager = .default) {
        self.converter = converter
        self.fileManager = fileManager
    }

    public func inspect(sourceDirectory: URL) throws -> LegacyStoreInfo {
        let databaseURL = sourceDirectory.appendingPathComponent("notes.db")
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw MigrationError.databaseMissing(databaseURL)
        }
        let connection = try SQLiteConnection(url: databaseURL, readOnly: true)
        guard try hasSupportedSchema(connection) else { throw MigrationError.unsupportedSchema }
        let counts = try countNotes(connection)
        let tags = try scalarInt(connection, sql: "SELECT COUNT(*) FROM Tags;")
        return LegacyStoreInfo(
            databaseURL: databaseURL,
            noteCount: counts.total,
            activeNoteCount: counts.active,
            deletedNoteCount: counts.deleted,
            tagCount: tags
        )
    }

    public func migrate(sourceDirectory: URL, targetVaultURL: URL, dryRun: Bool) throws -> MigrationReport {
        guard sourceDirectory.standardizedFileURL != targetVaultURL.standardizedFileURL else {
            throw MigrationError.sourceAndTargetMustDiffer
        }
        _ = try inspect(sourceDirectory: sourceDirectory)
        let databaseURL = sourceDirectory.appendingPathComponent("notes.db")
        let connection = try SQLiteConnection(url: databaseURL, readOnly: true)
        let legacyNotes = try fetchLegacyNotes(connection)
        let service = try VaultFileService(rootURL: targetVaultURL)
        let migrationID = migrationIdentifier(for: databaseURL)
        let migrationDirectory = service.metadataDirectory
            .appendingPathComponent("migrations", isDirectory: true)
            .appendingPathComponent(migrationID, isDirectory: true)
        let manifestURL = migrationDirectory.appendingPathComponent("manifest.json")
        var manifest = loadManifest(at: manifestURL)
            ?? MigrationManifest(
                version: 1,
                migrationID: migrationID,
                sourceDatabasePath: databaseURL.standardizedFileURL.path,
                backupPath: nil,
                entries: [],
                undoneAt: nil
            )

        if !dryRun, manifest.backupPath == nil {
            let backupURL = try createBackup(
                sourceDirectory: sourceDirectory,
                sourceConnection: connection,
                legacyNotes: legacyNotes,
                service: service,
                migrationID: migrationID
            )
            manifest.backupPath = backupURL.path
            try writeManifest(manifest, to: manifestURL)
        }

        var results: [MigrationItemResult] = []
        for legacy in legacyNotes {
            let previousEntry = manifest.entries.first(where: { $0.legacyID == legacy.id })
            if let existing = previousEntry, let existingPath = existing.notePath,
               fileManager.fileExists(atPath: service.vault.url(for: existingPath).path) {
                results.append(MigrationItemResult(
                    legacyID: legacy.id,
                    title: legacy.title,
                    outputPath: existing.outputPath,
                    status: .skippedAlreadyImported,
                    warnings: [],
                    error: nil
                ))
                continue
            }

            do {
                let conversion = try converter.convert(legacy.content)
                let defaultFolder = legacy.isDeleted ? try NotePath("Legacy Trash") : .root
                let preferredName = sanitizedTitle(legacy.title)
                let previousPath = previousEntry?.notePath
                let proposedPath = try previousPath
                    ?? proposedUniquePath(
                        service: service,
                        folder: defaultFolder,
                        preferredName: preferredName,
                        occupiedPaths: Set(manifest.entries.filter { $0.legacyID != legacy.id }.map(\.outputPath))
                    )
                let folder = proposedPath.parent

                if dryRun {
                    results.append(MigrationItemResult(
                        legacyID: legacy.id,
                        title: legacy.title,
                        outputPath: proposedPath.value,
                        status: .planned,
                        warnings: conversion.warnings,
                        error: nil
                    ))
                    continue
                }

                try service.ensureFolder(at: folder)
                let body = migratedMarkdown(for: legacy, convertedBody: conversion.markdown)
                let createdPath = try service.createNote(
                    in: folder,
                    preferredName: proposedPath.name,
                    markdown: body
                )
                let outputURL = service.url(for: createdPath)
                try? fileManager.setAttributes(
                    [.creationDate: legacy.createdAt, .modificationDate: legacy.updatedAt],
                    ofItemAtPath: outputURL.path
                )
                let data = try Data(contentsOf: outputURL)
                manifest.entries.removeAll { $0.legacyID == legacy.id }
                manifest.entries.append(MigrationManifestEntry(
                    legacyID: legacy.id,
                    outputPath: createdPath.value,
                    outputFingerprint: VaultRevision.fingerprint(of: data)
                ))
                manifest.undoneAt = nil
                try writeManifest(manifest, to: manifestURL)
                results.append(MigrationItemResult(
                    legacyID: legacy.id,
                    title: legacy.title,
                    outputPath: createdPath.value,
                    status: .imported,
                    warnings: conversion.warnings,
                    error: nil
                ))
            } catch {
                results.append(MigrationItemResult(
                    legacyID: legacy.id,
                    title: legacy.title,
                    outputPath: nil,
                    status: .failed,
                    warnings: [],
                    error: error.localizedDescription
                ))
            }
        }

        let report = MigrationReport(
            id: migrationID,
            sourceDatabasePath: databaseURL.path,
            targetVaultPath: targetVaultURL.path,
            generatedAt: Date(),
            dryRun: dryRun,
            backupPath: manifest.backupPath,
            items: results
        )
        if !dryRun {
            try writeReport(report, to: migrationDirectory)
            _ = try service.rebuildFileManifest()
        }
        return report
    }

    public func undo(sourceDirectory: URL, targetVaultURL: URL) throws -> MigrationUndoReport {
        guard sourceDirectory.standardizedFileURL != targetVaultURL.standardizedFileURL else {
            throw MigrationError.sourceAndTargetMustDiffer
        }
        let databaseURL = sourceDirectory.appendingPathComponent("notes.db")
        let service = try VaultFileService(rootURL: targetVaultURL)
        let migrationID = migrationIdentifier(for: databaseURL)
        let migrationDirectory = service.metadataDirectory
            .appendingPathComponent("migrations", isDirectory: true)
            .appendingPathComponent(migrationID, isDirectory: true)
        let manifestURL = migrationDirectory.appendingPathComponent("manifest.json")
        guard var manifest = loadManifest(at: manifestURL) else { throw MigrationError.noMigrationManifest }

        let undoRoot = service.metadataDirectory
            .appendingPathComponent("migration-undo", isDirectory: true)
            .appendingPathComponent("\(migrationID)-\(timestamp())", isDirectory: true)
        var moved: [String] = []
        var skipped: [String] = []
        for entry in manifest.entries {
            guard let notePath = entry.notePath else {
                skipped.append(entry.outputPath)
                continue
            }
            let sourceURL = service.vault.url(for: notePath)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            let data = try Data(contentsOf: sourceURL)
            guard VaultRevision.fingerprint(of: data) == entry.outputFingerprint else {
                skipped.append(entry.outputPath)
                continue
            }
            let destinationURL = notePath.components.reduce(undoRoot) {
                $0.appendingPathComponent($1)
            }
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            moved.append(entry.outputPath)
        }
        manifest.undoneAt = Date()
        try writeManifest(manifest, to: manifestURL)
        _ = try service.rebuildFileManifest()
        return MigrationUndoReport(restoredToUndoFolder: moved, skippedModifiedFiles: skipped)
    }

    private func hasSupportedSchema(_ connection: SQLiteConnection) throws -> Bool {
        let statement = try connection.prepare(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name IN ('Notes', 'Tags', 'NoteTags');"
        )
        return try statement.step() && statement.int64(at: 0) == 3
    }

    private func countNotes(_ connection: SQLiteConnection) throws -> (total: Int, active: Int, deleted: Int) {
        let statement = try connection.prepare(
            "SELECT COUNT(*), SUM(CASE WHEN IsDeleted = 0 THEN 1 ELSE 0 END), SUM(CASE WHEN IsDeleted = 1 THEN 1 ELSE 0 END) FROM Notes;"
        )
        guard try statement.step() else { return (0, 0, 0) }
        return (Int(statement.int64(at: 0)), Int(statement.int64(at: 1)), Int(statement.int64(at: 2)))
    }

    private func scalarInt(_ connection: SQLiteConnection, sql: String) throws -> Int {
        let statement = try connection.prepare(sql)
        return try statement.step() ? Int(statement.int64(at: 0)) : 0
    }

    private func fetchLegacyNotes(_ connection: SQLiteConnection) throws -> [LegacyNote] {
        let tagStatement = try connection.prepare(
            "SELECT nt.NoteId, t.Name FROM NoteTags nt INNER JOIN Tags t ON t.Id = nt.TagId ORDER BY t.Name COLLATE NOCASE;"
        )
        var tagsByNote: [Int64: [String]] = [:]
        while try tagStatement.step() {
            tagsByNote[tagStatement.int64(at: 0), default: []].append(tagStatement.string(at: 1))
        }

        let statement = try connection.prepare(
            "SELECT Id, Title, Content, MarkdownFileName, CreatedAt, UpdatedAt, IsPinned, IsDeleted FROM Notes ORDER BY Id;"
        )
        var result: [LegacyNote] = []
        while try statement.step() {
            let id = statement.int64(at: 0)
            result.append(LegacyNote(
                id: id,
                title: statement.string(at: 1),
                content: statement.string(at: 2),
                markdownFileName: statement.optionalString(at: 3),
                createdAt: DatabaseDateCoding.date(from: statement.string(at: 4)),
                updatedAt: DatabaseDateCoding.date(from: statement.string(at: 5)),
                isPinned: statement.bool(at: 6),
                isDeleted: statement.bool(at: 7),
                tags: tagsByNote[id] ?? []
            ))
        }
        return result
    }

    private func createBackup(
        sourceDirectory: URL,
        sourceConnection: SQLiteConnection,
        legacyNotes: [LegacyNote],
        service: VaultFileService,
        migrationID: String
    ) throws -> URL {
        let backupURL = service.metadataDirectory
            .appendingPathComponent("migration-backups", isDirectory: true)
            .appendingPathComponent("\(migrationID)-\(timestamp())", isDirectory: true)
        do {
            try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)
            try backupDatabase(sourceConnection, to: backupURL.appendingPathComponent("notes.db"))
            let settingsURL = sourceDirectory.appendingPathComponent("settings.json")
            if fileManager.fileExists(atPath: settingsURL.path) {
                try fileManager.copyItem(at: settingsURL, to: backupURL.appendingPathComponent("settings.json"))
            }
            let filesDirectory = backupURL.appendingPathComponent("legacy-markdown", isDirectory: true)
            try fileManager.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
            for fileName in Set(legacyNotes.compactMap(\.markdownFileName)) {
                let source = sourceDirectory.appendingPathComponent(fileName)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.copyItem(at: source, to: filesDirectory.appendingPathComponent(fileName))
            }
            return backupURL
        } catch {
            throw MigrationError.backupFailed(error.localizedDescription)
        }
    }

    private func backupDatabase(_ source: SQLiteConnection, to destinationURL: URL) throws {
        var destination: OpaquePointer?
        guard sqlite3_open_v2(
            destinationURL.path,
            &destination,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let destination else {
            throw MigrationError.backupFailed("Could not open the backup database.")
        }
        defer { sqlite3_close(destination) }
        guard let backup = sqlite3_backup_init(destination, "main", source.handle, "main") else {
            throw MigrationError.backupFailed(String(cString: sqlite3_errmsg(destination)))
        }
        let stepResult = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw MigrationError.backupFailed(String(cString: sqlite3_errmsg(destination)))
        }
    }

    private func migratedMarkdown(for note: LegacyNote, convertedBody: String) -> String {
        var lines = ["---"]
        lines.append("title: \(yamlString(note.title))")
        lines.append("created: \(yamlString(isoDate(note.createdAt)))")
        lines.append("updated: \(yamlString(isoDate(note.updatedAt)))")
        lines.append("legacy-id: \(note.id)")
        if note.isPinned { lines.append("pinned: true") }
        if note.isDeleted { lines.append("legacy-deleted: true") }
        if !note.tags.isEmpty {
            lines.append("tags:")
            lines.append(contentsOf: note.tags.map { "  - \(yamlString($0))" })
        }
        lines.append("---")
        if !convertedBody.isEmpty {
            lines.append("")
            lines.append(convertedBody)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func proposedUniquePath(
        service: VaultFileService,
        folder: NotePath,
        preferredName: String,
        occupiedPaths: Set<String>
    ) throws -> NotePath {
        var counter = 1
        while true {
            let suffix = counter == 1 ? "" : " \(counter)"
            let candidate = try folder.appending("\(preferredName)\(suffix).md")
            if !fileManager.fileExists(atPath: service.url(for: candidate).path), !occupiedPaths.contains(candidate.value) {
                return candidate
            }
            counter += 1
        }
    }

    private func sanitizedTitle(_ title: String) -> String {
        let value = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((value.isEmpty ? "Untitled" : value).prefix(180))
    }

    private func yamlString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    private func isoDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func migrationIdentifier(for databaseURL: URL) -> String {
        let data = Data(databaseURL.standardizedFileURL.path.utf8)
        return "legacy-" + String(VaultRevision.fingerprint(of: data), radix: 16)
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func loadManifest(at url: URL) -> MigrationManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MigrationManifest.self, from: data)
    }

    private func writeManifest(_ manifest: MigrationManifest, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: url, options: .atomic)
    }

    private func writeReport(_ report: MigrationReport, to directory: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let stem = "report-\(timestamp())"
        try encoder.encode(report).write(to: directory.appendingPathComponent(stem + ".json"), options: .atomic)

        var markdown = "# Legacy migration report\n\n"
        markdown += "- Source: `\(report.sourceDatabasePath)`\n"
        markdown += "- Target: `\(report.targetVaultPath)`\n"
        markdown += "- Imported: \(report.importedCount)\n"
        markdown += "- Already imported: \(report.skippedCount)\n"
        markdown += "- Failed: \(report.failedCount)\n\n"
        for item in report.items {
            markdown += "- \(item.status.rawValue): \(item.title)"
            if let path = item.outputPath { markdown += " → `\(path)`" }
            if let error = item.error { markdown += " — \(error)" }
            markdown += "\n"
        }
        try markdown.write(to: directory.appendingPathComponent(stem + ".md"), atomically: true, encoding: .utf8)
    }
}

private struct LegacyNote {
    let id: Int64
    let title: String
    let content: String
    let markdownFileName: String?
    let createdAt: Date
    let updatedAt: Date
    let isPinned: Bool
    let isDeleted: Bool
    let tags: [String]
}

private struct MigrationManifest: Codable {
    var version: Int
    var migrationID: String
    var sourceDatabasePath: String
    var backupPath: String?
    var entries: [MigrationManifestEntry]
    var undoneAt: Date?
}

private struct MigrationManifestEntry: Codable {
    let legacyID: Int64
    let outputPath: String
    let outputFingerprint: UInt64

    var notePath: NotePath? { try? NotePath(outputPath) }
}
