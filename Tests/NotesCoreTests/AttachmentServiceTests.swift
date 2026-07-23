import Foundation
import XCTest
@testable import NotesCore

final class AttachmentServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesAttachmentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }

    func testConfigurableLocationsEmbedsAndAudit() throws {
        let files = try VaultFileService(rootURL: root)
        let folder = try files.createFolder(in: .root, preferredName: "Notes")
        let notePath = try files.createNote(in: folder, preferredName: "Media", markdown: "")
        let service = try AttachmentService(vaultURL: root)
        var settings = VaultSettings()
        settings.attachmentLocation = .subfolder
        settings.attachmentSubfolderName = "assets"

        let image = try service.save(
            data: Data([1, 2, 3]), preferredName: "image with spaces.png",
            for: notePath, settings: settings
        )
        XCTAssertEqual(image.value, "Notes/assets/image with spaces.png")
        let embed = service.embedMarkdown(for: image, from: notePath, width: 320)
        XCTAssertEqual(embed, "![[Notes/assets/image with spaces.png|320]]")
        let note = try files.readNote(at: notePath)
        _ = try files.writeNote(at: notePath, markdown: embed, expectedRevision: note.revision)

        XCTAssertEqual(try service.audit(), AttachmentAudit(missingReferences: [], unusedAttachments: []))
        _ = try service.save(data: Data([4]), preferredName: "unused.pdf", for: notePath, settings: settings)
        XCTAssertEqual(try service.audit().unusedAttachments.map(\.name), ["unused.pdf"])
    }

    func testMissingAttachmentIsReportedWithoutChangingNote() throws {
        let files = try VaultFileService(rootURL: root)
        let notePath = try files.createNote(in: .root, preferredName: "Missing", markdown: "![[missing.pdf#page=3]]")
        let audit = try AttachmentService(vaultURL: root).audit()
        XCTAssertEqual(audit.missingReferences, ["\(notePath.value): missing.pdf"])
        XCTAssertEqual(try files.readNote(at: notePath).markdown, "![[missing.pdf#page=3]]")
    }
}
