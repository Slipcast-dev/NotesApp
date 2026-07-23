import Foundation
import XCTest
@testable import NotesCore

final class MetadataIndexTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        roots.removeAll()
    }

    func testIncrementalFTSSearchLinksTasksAndProperties() async throws {
        let root = try makeRoot()
        let files = try VaultFileService(rootURL: root)
        let alpha = try files.createNote(in: .root, preferredName: "Alpha", markdown: """
        ---
        tags: [work, swift]
        status: active
        aliases: [First]
        ---
        # Alpha heading

        Exact searchable phrase.

        - [ ] Open task

        [[Folder/Beta#Section|Beta alias]]
        """)
        let folder = try files.createFolder(in: .root, preferredName: "Folder")
        let beta = try files.createNote(in: folder, preferredName: "Beta", markdown: """
        # Section ^section

        Beta body with Alpha mention.
        """)

        let metadata = try MetadataIndex(vaultURL: root)
        let initial = try await metadata.synchronize()
        XCTAssertEqual(initial.indexed, 2)
        XCTAssertEqual(initial.unchanged, 0)

        let search = try SearchIndex(vaultURL: root)
        XCTAssertEqual(try await search.search("\"searchable phrase\"").map(\.path), [alpha])
        XCTAssertEqual(try await search.search("tag:work property:status=active task:unchecked").map(\.path), [alpha])
        XCTAssertEqual(try await search.search("path:Folder Beta").map(\.path), [beta])
        XCTAssertEqual(try await search.search("/Exact searchable/").map(\.path), [alpha])
        XCTAssertEqual(try await search.search("regex:Exact searchable").map(\.path), [alpha])

        let outgoing = try await metadata.outgoingLinks(from: alpha)
        XCTAssertEqual(outgoing.first?.destination, "Folder/Beta")
        XCTAssertEqual(outgoing.first?.heading, "Section")
        let backlinks = try await metadata.backlinks(to: ["Folder/Beta"])
        XCTAssertEqual(backlinks.map(\.sourcePath), [alpha])
        XCTAssertTrue(backlinks.first?.context.contains("[[Folder/Beta") == true)
        XCTAssertEqual(try await metadata.headings(in: beta).first?.blockID, "section")

        let opened = try files.readNote(at: beta)
        _ = try files.writeNote(at: beta, markdown: opened.markdown + "\nnew token", expectedRevision: opened.revision)
        let incremental = try await metadata.synchronize()
        XCTAssertEqual(incremental.indexed, 1)
        XCTAssertEqual(incremental.unchanged, 1)
        XCTAssertEqual(try await search.search("\"new token\"").map(\.path), [beta])
    }

    func testDeletedOrCorruptIndexRebuildsFromMarkdown() async throws {
        let root = try makeRoot()
        let files = try VaultFileService(rootURL: root)
        _ = try files.createNote(in: .root, preferredName: "Recover", markdown: "recoverable body")
        var metadata: MetadataIndex? = try MetadataIndex(vaultURL: root)
        _ = try await metadata?.synchronize()
        metadata = nil

        let database = root.appendingPathComponent(".notesapp/index.sqlite")
        try FileManager.default.removeItem(at: database)
        var rebuilt: MetadataIndex? = try MetadataIndex(vaultURL: root)
        XCTAssertEqual(try await rebuilt?.synchronize().indexed, 1)
        rebuilt = nil

        // A corrupt cache is quarantined; Markdown remains untouched and is re-indexed.
        try? FileManager.default.removeItem(at: database)
        try Data("not sqlite".utf8).write(to: database)
        let recovered = try MetadataIndex(vaultURL: root)
        XCTAssertEqual(try await recovered.synchronize().indexed, 1)
        XCTAssertEqual(try files.readNote(at: try NotePath("Recover.md")).markdown, "recoverable body")
    }

    func testSearchQueryParserOperators() {
        let parsed = SearchQueryParser().parse(#""exact phrase" AND notes path:"Daily Notes" tag:#work property:status=done task:checked block:project"#)
        XCTAssertEqual(parsed.fullTextQuery, #""exact phrase" AND notes"#)
        XCTAssertEqual(parsed.filters, [
            .path("Daily Notes"), .tag("work"), .property(key: "status", value: "done"),
            .task(.checked), .block("project")
        ])
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesIndexTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        roots.append(root)
        return root
    }
}
