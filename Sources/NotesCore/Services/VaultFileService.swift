import Foundation

public enum VaultFileError: LocalizedError {
    case invalidVault(URL)
    case invalidName(String)
    case itemNotFound(NotePath)
    case destinationExists(NotePath)
    case destinationIsNotFolder(NotePath)
    case cannotMoveFolderIntoItself
    case cannotModifyRoot
    case unsupportedTextEncoding(NotePath)
    case externallyModified(path: NotePath, diskMarkdown: String)
    case externallyRemoved(NotePath)

    public var errorDescription: String? {
        switch self {
        case .invalidVault(let url): return "The selected vault is not a readable folder: \(url.path)"
        case .invalidName(let name): return "Invalid file name: \(name)"
        case .itemNotFound(let path): return "Vault item not found: \(path.value)"
        case .destinationExists(let path): return "An item already exists at: \(path.value)"
        case .destinationIsNotFolder(let path): return "Destination is not a folder: \(path.value)"
        case .cannotMoveFolderIntoItself: return "A folder cannot be moved inside itself."
        case .cannotModifyRoot: return "The vault root cannot be renamed, moved, duplicated, or deleted."
        case .unsupportedTextEncoding(let path): return "The note is not valid UTF-8: \(path.value)"
        case .externallyModified(let path, _): return "The note changed outside NotesApp: \(path.value)"
        case .externallyRemoved(let path): return "The note was removed outside NotesApp: \(path.value)"
        }
    }
}

public final class VaultFileService {
    public let vault: Vault
    public let metadataDirectory: URL
    public let settingsURL: URL
    public let fileManifestURL: URL

    private let fileManager: FileManager
    private let excludedNames: Set<String> = [".notesapp", ".obsidian", ".git", ".DS_Store"]

    public init(rootURL: URL, fileManager: FileManager = .default, createIfNeeded: Bool = true) throws {
        self.fileManager = fileManager
        vault = Vault(rootURL: rootURL)
        metadataDirectory = vault.rootURL.appendingPathComponent(".notesapp", isDirectory: true)
        settingsURL = metadataDirectory.appendingPathComponent("settings.json")
        fileManifestURL = metadataDirectory.appendingPathComponent("file-manifest.json")

        if createIfNeeded {
            try fileManager.createDirectory(at: vault.rootURL, withIntermediateDirectories: true)
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: vault.rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw VaultFileError.invalidVault(vault.rootURL)
        }
        try fileManager.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
    }

    public func loadSettings() -> VaultSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(VaultSettings.self, from: data) else {
            return VaultSettings()
        }
        return settings
    }

    public func saveSettings(_ settings: VaultSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(settings).write(to: settingsURL, options: .atomic)
    }

    public func snapshot() throws -> VaultSnapshot {
        var notes: [VaultNoteMetadata] = []
        let tree = try scanDirectory(.root, notes: &notes)
        notes.sort {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.path < $1.path
        }
        return VaultSnapshot(tree: tree, notes: notes)
    }

    public func rebuildFileManifest() throws -> VaultSnapshot {
        let snapshot = try snapshot()
        let records = snapshot.notes.map {
            FileManifestRecord(path: $0.path.value, modifiedAt: $0.modifiedAt, fileSize: $0.fileSize)
        }
        let manifest = FileManifest(version: 1, generatedAt: Date(), notes: records)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: fileManifestURL, options: .atomic)
        return snapshot
    }

    public func readNote(at path: NotePath) throws -> VaultNote {
        let url = vault.url(for: path)
        guard fileManager.fileExists(atPath: url.path) else { throw VaultFileError.itemNotFound(path) }
        let data = try Data(contentsOf: url)
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw VaultFileError.unsupportedTextEncoding(path)
        }
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        let modifiedAt = values.contentModificationDate ?? .distantPast
        return VaultNote(
            path: path,
            markdown: markdown,
            revision: VaultRevision(
                modifiedAt: modifiedAt,
                byteCount: data.count,
                fingerprint: VaultRevision.fingerprint(of: data)
            ),
            createdAt: values.creationDate ?? modifiedAt
        )
    }

    @discardableResult
    public func writeNote(
        at path: NotePath,
        markdown: String,
        expectedRevision: VaultRevision?,
        force: Bool = false
    ) throws -> VaultNote {
        let url = vault.url(for: path)
        guard fileManager.fileExists(atPath: url.path) else { throw VaultFileError.externallyRemoved(path) }

        if !force, let expectedRevision {
            let diskData = try Data(contentsOf: url)
            let diskFingerprint = VaultRevision.fingerprint(of: diskData)
            if diskFingerprint != expectedRevision.fingerprint {
                guard let diskMarkdown = String(data: diskData, encoding: .utf8) else {
                    throw VaultFileError.unsupportedTextEncoding(path)
                }
                throw VaultFileError.externallyModified(path: path, diskMarkdown: diskMarkdown)
            }
        }

        guard let data = markdown.data(using: .utf8) else {
            throw VaultFileError.unsupportedTextEncoding(path)
        }
        try data.write(to: url, options: .atomic)
        return try readNote(at: path)
    }

    @discardableResult
    public func createNote(in folder: NotePath, preferredName: String = "Untitled", markdown: String = "") throws -> NotePath {
        try requireFolder(folder)
        let base = try validLeafName(preferredName)
        let fileName = base.lowercased().hasSuffix(".md") ? base : base + ".md"
        let path = try uniquePath(in: folder, preferredName: fileName)
        guard let data = markdown.data(using: .utf8) else {
            throw VaultFileError.unsupportedTextEncoding(path)
        }
        try createFileAtomically(data, at: vault.url(for: path))
        return path
    }

    @discardableResult
    public func createFolder(in parent: NotePath, preferredName: String = "New folder") throws -> NotePath {
        try requireFolder(parent)
        let name = try validLeafName(preferredName)
        let path = try uniquePath(in: parent, preferredName: name)
        try fileManager.createDirectory(at: vault.url(for: path), withIntermediateDirectories: false)
        return path
    }

    public func ensureFolder(at path: NotePath) throws {
        var current = NotePath.root
        for component in path.components {
            current = try current.appending(component)
            let url = vault.url(for: current)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else { throw VaultFileError.destinationIsNotFolder(current) }
            } else {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
            }
        }
    }

    @discardableResult
    public func createAttachment(data: Data, in folder: NotePath, preferredName: String) throws -> NotePath {
        try requireFolder(folder)
        let name = try validLeafName(preferredName)
        let path = try uniquePath(in: folder, preferredName: name)
        try createFileAtomically(data, at: vault.url(for: path))
        return path
    }

    @discardableResult
    public func rename(_ path: NotePath, to newName: String) throws -> NotePath {
        guard !path.isRoot else { throw VaultFileError.cannotModifyRoot }
        let sourceURL = vault.url(for: path)
        guard fileManager.fileExists(atPath: sourceURL.path) else { throw VaultFileError.itemNotFound(path) }
        var leaf = try validLeafName(newName)
        if path.pathExtension.lowercased() == "md", !leaf.lowercased().hasSuffix(".md") {
            leaf += ".md"
        }
        let destination = try path.parent.appending(leaf)
        guard destination != path else { return path }
        try requireAvailable(destination)
        try fileManager.moveItem(at: sourceURL, to: vault.url(for: destination))
        return destination
    }

    @discardableResult
    public func move(_ path: NotePath, into destinationFolder: NotePath) throws -> NotePath {
        guard !path.isRoot else { throw VaultFileError.cannotModifyRoot }
        try requireFolder(destinationFolder)
        if destinationFolder == path || destinationFolder.isDescendant(of: path) {
            throw VaultFileError.cannotMoveFolderIntoItself
        }
        let destination = try destinationFolder.appending(path.name)
        guard destination != path else { return path }
        try requireAvailable(destination)
        let sourceURL = vault.url(for: path)
        guard fileManager.fileExists(atPath: sourceURL.path) else { throw VaultFileError.itemNotFound(path) }
        try fileManager.moveItem(at: sourceURL, to: vault.url(for: destination))
        return destination
    }

    @discardableResult
    public func duplicate(_ path: NotePath) throws -> NotePath {
        guard !path.isRoot else { throw VaultFileError.cannotModifyRoot }
        let sourceURL = vault.url(for: path)
        guard fileManager.fileExists(atPath: sourceURL.path) else { throw VaultFileError.itemNotFound(path) }
        let ext = (path.name as NSString).pathExtension
        let stem = (path.name as NSString).deletingPathExtension
        let preferred = ext.isEmpty ? "\(stem) copy" : "\(stem) copy.\(ext)"
        let destination = try uniquePath(in: path.parent, preferredName: preferred)
        try fileManager.copyItem(at: sourceURL, to: vault.url(for: destination))
        return destination
    }

    public func trash(_ path: NotePath) throws {
        guard !path.isRoot else { throw VaultFileError.cannotModifyRoot }
        let url = vault.url(for: path)
        guard fileManager.fileExists(atPath: url.path) else { throw VaultFileError.itemNotFound(path) }
        var resultingURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
    }

    public func url(for path: NotePath) -> URL {
        vault.url(for: path)
    }

    private func scanDirectory(_ directory: NotePath, notes: inout [VaultNoteMetadata]) throws -> [VaultItem] {
        let urls = try fileManager.contentsOfDirectory(
            at: vault.url(for: directory),
            includingPropertiesForKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                .contentModificationDateKey, .creationDateKey, .fileSizeKey
            ],
            options: []
        )
        var items: [VaultItem] = []

        for url in urls where !excludedNames.contains(url.lastPathComponent) {
            let path = try directory.appending(url.lastPathComponent)
            let values = try url.resourceValues(forKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                .contentModificationDateKey, .creationDateKey, .fileSizeKey
            ])
            if values.isSymbolicLink == true {
                items.append(VaultItem(path: path, kind: .attachment, modificationDate: values.contentModificationDate))
            } else if values.isDirectory == true {
                items.append(VaultItem(
                    path: path,
                    kind: .folder,
                    children: try scanDirectory(path, notes: &notes),
                    modificationDate: values.contentModificationDate
                ))
            } else if values.isRegularFile == true {
                let size = Int64(values.fileSize ?? 0)
                let modified = values.contentModificationDate ?? .distantPast
                let kind: VaultItemKind = url.pathExtension.lowercased() == "md" ? .note : .attachment
                items.append(VaultItem(path: path, kind: kind, modificationDate: modified, fileSize: size))
                if kind == .note {
                    notes.append(VaultNoteMetadata(
                        path: path,
                        createdAt: values.creationDate ?? modified,
                        modifiedAt: modified,
                        fileSize: size
                    ))
                }
            }
        }

        return items.sorted { lhs, rhs in
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func requireFolder(_ path: NotePath) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: vault.url(for: path).path, isDirectory: &isDirectory) else {
            throw VaultFileError.itemNotFound(path)
        }
        guard isDirectory.boolValue else { throw VaultFileError.destinationIsNotFolder(path) }
    }

    private func requireAvailable(_ path: NotePath) throws {
        guard !fileManager.fileExists(atPath: vault.url(for: path).path) else {
            throw VaultFileError.destinationExists(path)
        }
    }

    private func uniquePath(in folder: NotePath, preferredName: String) throws -> NotePath {
        let ext = (preferredName as NSString).pathExtension
        let stem = (preferredName as NSString).deletingPathExtension
        var counter = 0
        while true {
            let suffix = counter == 0 ? "" : " \(counter + 1)"
            let name = ext.isEmpty ? "\(stem)\(suffix)" : "\(stem)\(suffix).\(ext)"
            let candidate = try folder.appending(name)
            if !fileManager.fileExists(atPath: vault.url(for: candidate).path) {
                return candidate
            }
            counter += 1
        }
    }

    private func validLeafName(_ rawName: String) throws -> String {
        let value = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value != ".", value != "..",
              !value.contains("/"), !value.contains("\\"), !value.contains("\0") else {
            throw VaultFileError.invalidName(rawName)
        }
        return value
    }

    private func createFileAtomically(_ data: Data, at destinationURL: URL) throws {
        let temporaryURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".notesapp-write-\(UUID().uuidString)")
        do {
            try data.write(to: temporaryURL, options: .withoutOverwriting)
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}

private struct FileManifest: Codable {
    let version: Int
    let generatedAt: Date
    let notes: [FileManifestRecord]
}

private struct FileManifestRecord: Codable {
    let path: String
    let modifiedAt: Date
    let fileSize: Int64
}
