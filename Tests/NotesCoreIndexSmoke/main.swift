import Foundation
import NotesCore

enum IndexSmokeFailure: Error {
    case assertion(String)
}

@main
struct NotesCoreIndexSmoke {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesIndexSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let files = try VaultFileService(rootURL: root)
        let alpha = try files.createNote(in: .root, preferredName: "Alpha", markdown: """
        ---
        tags: [work]
        status: active
        ---
        # Alpha

        Searchable phrase.

        - [ ] Task

        [[Beta]]
        """)
        _ = try files.createNote(in: .root, preferredName: "Beta", markdown: "# Beta\n")
        let metadata = try MetadataIndex(vaultURL: root)
        let indexed = try await metadata.synchronize()
        try require(indexed.indexed == 2, "Expected two indexed notes")

        let search = try SearchIndex(vaultURL: root)
        let phraseResults = try await search.search("\"Searchable phrase\"").map(\.path)
        let filteredResults = try await search.search("tag:work property:status=active task:unchecked").map(\.path)
        let backlinks = try await metadata.backlinks(to: ["Beta"]).map(\.sourcePath)
        try require(phraseResults == [alpha], "FTS phrase search failed")
        try require(filteredResults == [alpha], "Filtered search failed")
        try require(backlinks == [alpha], "Backlink index failed")

        let second = try await metadata.synchronize()
        try require(second.unchanged == 2, "Incremental indexing did not skip unchanged files")
        print("NotesCore metadata/search index smoke test passed")
    }

    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw IndexSmokeFailure.assertion(message) }
    }
}
