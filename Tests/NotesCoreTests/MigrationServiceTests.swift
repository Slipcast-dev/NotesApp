import AppKit
import Foundation
import XCTest
@testable import NotesCore

final class MigrationServiceTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        roots.removeAll()
    }

    func testRTFFormattingIsConvertedToMarkdown() throws {
        let source = NSMutableAttributedString(string: "Heading\nBold italic\n☐ Open\n☑ Done")
        source.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 24), range: NSRange(location: 0, length: 7))
        source.addAttribute(.font, value: NSFontManager.shared.convert(
            NSFont.boldSystemFont(ofSize: 14), toHaveTrait: .italicFontMask
        ), range: NSRange(location: 8, length: 11))

        let result = try RTFMarkdownConverter().convert(try rtfString(source))
        XCTAssertTrue(result.markdown.contains("# **Heading**"))
        XCTAssertTrue(result.markdown.contains("***Bold italic***"))
        XCTAssertTrue(result.markdown.contains("- [ ] Open"))
        XCTAssertTrue(result.markdown.contains("- [x] Done"))
        XCTAssertFalse(result.markdown.contains("{\\rtf"))
    }

    func testDryRunBackupMigrationIdempotencyAndUndo() throws {
        let sourceRoot = try makeRoot()
        let targetRoot = try makeRoot()
        let database = try DatabaseService(directory: sourceRoot)
        let attributed = NSMutableAttributedString(string: "Bold\n☐ Task")
        attributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14), range: NSRange(location: 0, length: 4))
        let note = try database.createNote(title: "Project / Alpha", content: try rtfString(attributed))
        let tag = try database.createTag(name: "work", colorHex: nil)
        try database.addTag(tag.id, toNote: note.id)

        let migration = MigrationService()
        let dryRun = try migration.migrate(sourceDirectory: sourceRoot, targetVaultURL: targetRoot, dryRun: true)
        XCTAssertEqual(dryRun.items.map(\.status), [.planned])
        XCTAssertTrue(try VaultFileService(rootURL: targetRoot).snapshot().notes.isEmpty)

        let report = try migration.migrate(sourceDirectory: sourceRoot, targetVaultURL: targetRoot, dryRun: false)
        XCTAssertEqual(report.importedCount, 1)
        XCTAssertNotNil(report.backupPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.backupPath!))

        let path = try NotePath(XCTUnwrap(report.items.first?.outputPath))
        let migrated = try VaultFileService(rootURL: targetRoot).readNote(at: path)
        XCTAssertTrue(migrated.markdown.contains("title: \"Project / Alpha\""))
        XCTAssertTrue(migrated.markdown.contains("tags:\n  - \"work\""))
        XCTAssertTrue(migrated.markdown.contains("**Bold**"))
        XCTAssertFalse(migrated.markdown.contains("{\\rtf"))

        let repeated = try migration.migrate(sourceDirectory: sourceRoot, targetVaultURL: targetRoot, dryRun: false)
        XCTAssertEqual(repeated.skippedCount, 1)
        XCTAssertEqual(try VaultFileService(rootURL: targetRoot).snapshot().notes.count, 1)

        let undo = try migration.undo(sourceDirectory: sourceRoot, targetVaultURL: targetRoot)
        XCTAssertEqual(undo.restoredToUndoFolder, [path.value])
        XCTAssertTrue(undo.skippedModifiedFiles.isEmpty)
        XCTAssertTrue(try VaultFileService(rootURL: targetRoot).snapshot().notes.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent("notes.db").path))
    }

    func testUndoKeepsFilesEditedAfterMigration() throws {
        let sourceRoot = try makeRoot()
        let targetRoot = try makeRoot()
        let database = try DatabaseService(directory: sourceRoot)
        _ = try database.createNote(title: "Edited", content: "original")
        let migration = MigrationService()
        let report = try migration.migrate(sourceDirectory: sourceRoot, targetVaultURL: targetRoot, dryRun: false)
        let path = try NotePath(XCTUnwrap(report.items.first?.outputPath))
        try "user edit".write(
            to: Vault(rootURL: targetRoot).url(for: path),
            atomically: true,
            encoding: .utf8
        )

        let undo = try migration.undo(sourceDirectory: sourceRoot, targetVaultURL: targetRoot)
        XCTAssertEqual(undo.skippedModifiedFiles, [path.value])
        XCTAssertEqual(try VaultFileService(rootURL: targetRoot).readNote(at: path).markdown, "user edit")
    }

    private func rtfString(_ attributed: NSAttributedString) throws -> String {
        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        roots.append(root)
        return root
    }
}
