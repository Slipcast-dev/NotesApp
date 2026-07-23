import Foundation
import XCTest
@testable import NotesCore

final class VaultFileServiceTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots where FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
    }

    func testMarkdownFilesAreTheSourceOfTruthAndRemainPlainUTF8() throws {
        let service = try makeService()
        let path = try service.createNote(
            in: .root,
            preferredName: "Привет мир",
            markdown: "# Заголовок\n\n**Жирный**, [[Связь]] и ✅"
        )

        XCTAssertEqual(path.value, "Привет мир.md")
        let note = try service.readNote(at: path)
        XCTAssertEqual(note.markdown, "# Заголовок\n\n**Жирный**, [[Связь]] и ✅")
        XCTAssertFalse(note.markdown.contains("{\\rtf"))

        let raw = try String(contentsOf: service.url(for: path), encoding: .utf8)
        XCTAssertEqual(raw, note.markdown)
        XCTAssertEqual(try service.snapshot().notes.map(\.path), [path])
    }

    func testFoldersAllowSameNoteNameAndOperationsPreserveContent() throws {
        let service = try makeService()
        let firstFolder = try service.createFolder(in: .root, preferredName: "Проекты A")
        let secondFolder = try service.createFolder(in: .root, preferredName: "Проекты B")
        let first = try service.createNote(in: firstFolder, preferredName: "План", markdown: "alpha")
        let second = try service.createNote(in: secondFolder, preferredName: "План", markdown: "beta")

        XCTAssertNotEqual(first, second)
        let renamed = try service.rename(first, to: "План финальный")
        XCTAssertEqual(renamed.value, "Проекты A/План финальный.md")
        XCTAssertEqual(try service.readNote(at: renamed).markdown, "alpha")

        let duplicate = try service.duplicate(renamed)
        XCTAssertEqual(duplicate.value, "Проекты A/План финальный copy.md")
        let moved = try service.move(duplicate, into: secondFolder)
        XCTAssertEqual(moved.value, "Проекты B/План финальный copy.md")
        XCTAssertEqual(try service.readNote(at: moved).markdown, "alpha")
        XCTAssertEqual(try service.readNote(at: second).markdown, "beta")
    }

    func testAtomicWriteDetectsExternalEditInsteadOfOverwritingIt() throws {
        let service = try makeService()
        let path = try service.createNote(in: .root, preferredName: "Conflict", markdown: "base")
        let opened = try service.readNote(at: path)

        try "external".write(to: service.url(for: path), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(
            try service.writeNote(at: path, markdown: "mine", expectedRevision: opened.revision)
        ) { error in
            guard case VaultFileError.externallyModified(let conflictPath, let diskMarkdown) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(conflictPath, path)
            XCTAssertEqual(diskMarkdown, "external")
        }
        XCTAssertEqual(try service.readNote(at: path).markdown, "external")

        let forced = try service.writeNote(at: path, markdown: "mine", expectedRevision: opened.revision, force: true)
        XCTAssertEqual(forced.markdown, "mine")
    }

    func testManifestCanBeDeletedAndRebuiltFromFiles() throws {
        let service = try makeService()
        _ = try service.createNote(in: .root, preferredName: "One", markdown: "1")
        let folder = try service.createFolder(in: .root, preferredName: "Nested")
        _ = try service.createNote(in: folder, preferredName: "Two", markdown: "2")

        let first = try service.rebuildFileManifest()
        XCTAssertEqual(first.notes.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.fileManifestURL.path))

        try FileManager.default.removeItem(at: service.fileManifestURL)
        let second = try service.rebuildFileManifest()
        XCTAssertEqual(Set(second.notes.map(\.path.value)), ["One.md", "Nested/Two.md"])
    }

    func testVaultSettingsAndBookmarkRegistryAreReplaceableMetadata() throws {
        let root = try makeRoot()
        let service = try VaultFileService(rootURL: root)
        var settings = VaultSettings()
        settings.newNoteLocation = .specifiedFolder
        settings.newNoteFolder = "Inbox/Сегодня"
        try service.saveSettings(settings)
        XCTAssertEqual(service.loadSettings(), settings)

        let registryRoot = try makeRoot()
        let bookmarks = SecurityScopedBookmarkStore(applicationSupportDirectory: registryRoot)
        try bookmarks.save(root)
        XCTAssertEqual(bookmarks.restoreLast()?.standardizedFileURL, root.standardizedFileURL)
    }

    private func makeService() throws -> VaultFileService {
        try VaultFileService(rootURL: makeRoot())
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesAppTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        temporaryRoots.append(root)
        return root
    }
}
