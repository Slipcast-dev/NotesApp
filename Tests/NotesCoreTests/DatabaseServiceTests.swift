import Foundation
import XCTest
@testable import NotesCore

final class DatabaseServiceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testNoteTagTrashAndMarkdownRoundTrip() throws {
        let database = try DatabaseService(directory: temporaryDirectory)
        var note = try database.createNote(title: "Ventura", content: "First version")
        XCTAssertEqual(try database.fetchNotes().map(\.title), ["Ventura"])

        note = try database.updateNote(note, title: "Ventura note", content: "Updated body")
        let tag = try database.createTag(name: "macOS", colorHex: "#8E44AD")
        try database.addTag(tag.id, toNote: note.id)

        let loaded = try XCTUnwrap(database.fetchNote(id: note.id))
        XCTAssertEqual(loaded.content, "Updated body")
        XCTAssertEqual(loaded.tags, [tag])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: temporaryDirectory.appendingPathComponent("note-000001.md").path
        ))

        XCTAssertTrue(try database.moveToTrash(noteID: note.id))
        XCTAssertTrue(try database.fetchNotes().isEmpty)
        XCTAssertEqual(try database.fetchNotes(includeDeleted: true, onlyDeleted: true).count, 1)

        XCTAssertTrue(try database.restore(noteID: note.id))
        XCTAssertEqual(try database.fetchNotes().count, 1)
    }

    func testWindowsStyleSettingsJSONDecodes() throws {
        let json = """
        {
          "Theme": "Dark",
          "FontSize": 18,
          "FontFamily": "Arial",
          "AutoSave": false,
          "DefaultSorting": "titleasc",
          "Language": "en"
        }
        """
        try json.write(
            to: temporaryDirectory.appendingPathComponent("settings.json"),
            atomically: true,
            encoding: .utf8
        )

        let settings = SettingsService(directory: temporaryDirectory).load()
        XCTAssertEqual(settings.theme, .dark)
        XCTAssertEqual(settings.fontSize, 18)
        XCTAssertEqual(settings.defaultSorting, .titleAscending)
        XCTAssertEqual(settings.language, .english)
        XCTAssertFalse(settings.autoSave)
    }
}
