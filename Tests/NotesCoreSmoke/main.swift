import AppKit
import Foundation
import NotesCore

enum SmokeFailure: Error {
    case assertion(String)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw SmokeFailure.assertion(message) }
}

let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("NotesAppSmoke-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: root) }

let service = try VaultFileService(rootURL: root)
let unicodeFolder = try service.createFolder(in: .root, preferredName: "Работа 2026")
let path = try service.createNote(
    in: unicodeFolder,
    preferredName: "План",
    markdown: "# План\n\n- [ ] Проверить Markdown\n\n[[Связь]]"
)
let opened = try service.readNote(at: path)
try require(opened.markdown.hasPrefix("# План"), "Markdown read failed")
try require(!opened.markdown.contains("{\\rtf"), "RTF leaked into Markdown")

try "external edit".write(to: service.url(for: path), atomically: true, encoding: .utf8)
do {
    _ = try service.writeNote(at: path, markdown: "should not win", expectedRevision: opened.revision)
    throw SmokeFailure.assertion("External edit was overwritten")
} catch VaultFileError.externallyModified(_, let diskMarkdown) {
    try require(diskMarkdown == "external edit", "Conflict did not preserve disk contents")
}

let rebuilt = try service.rebuildFileManifest()
try require(rebuilt.notes.count == 1, "File manifest was not rebuilt")
try require(FileManager.default.fileExists(atPath: service.fileManifestURL.path), "Manifest file missing")

let duplicate = try service.duplicate(path)
let duplicateNote = try service.readNote(at: duplicate)
try require(duplicateNote.markdown == "external edit", "Duplicate content mismatch")
let renamed = try service.rename(duplicate, to: "Копия")
try require(renamed.value == "Работа 2026/Копия.md", "Rename produced an unexpected path")

let legacyRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("NotesAppLegacy-\(UUID().uuidString)", isDirectory: true)
let migratedRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("NotesAppMigrated-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: false)
try FileManager.default.createDirectory(at: migratedRoot, withIntermediateDirectories: false)
defer {
    try? FileManager.default.removeItem(at: legacyRoot)
    try? FileManager.default.removeItem(at: migratedRoot)
}

let attributed = NSMutableAttributedString(string: "Bold heading\n☐ Task")
attributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14), range: NSRange(location: 0, length: 4))
let rtfData = try attributed.data(
    from: NSRange(location: 0, length: attributed.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
)
let rtf = String(data: rtfData, encoding: .utf8)!
let legacyDatabase = try DatabaseService(directory: legacyRoot)
let legacyNote = try legacyDatabase.createNote(title: "Legacy / Note", content: rtf)
let legacyTag = try legacyDatabase.createTag(name: "imported", colorHex: nil)
try legacyDatabase.addTag(legacyTag.id, toNote: legacyNote.id)

let migration = MigrationService()
let dryRun = try migration.migrate(sourceDirectory: legacyRoot, targetVaultURL: migratedRoot, dryRun: true)
try require(dryRun.items.first?.status == .planned, "Migration dry run failed")
let migrationReport = try migration.migrate(sourceDirectory: legacyRoot, targetVaultURL: migratedRoot, dryRun: false)
try require(migrationReport.importedCount == 1, "Legacy note was not imported")
let migratedPath = try NotePath(migrationReport.items[0].outputPath!)
let migratedNote = try VaultFileService(rootURL: migratedRoot).readNote(at: migratedPath)
try require(migratedNote.markdown.contains("**Bold**"), "Bold RTF was not converted")
try require(migratedNote.markdown.contains("- [ ] Task"), "Checklist RTF was not converted")
try require(migratedNote.markdown.contains("  - \"imported\""), "Tags were not written to YAML")
try require(!migratedNote.markdown.contains("{\\rtf"), "Migrated Markdown still contains RTF")
let repeatedMigration = try migration.migrate(sourceDirectory: legacyRoot, targetVaultURL: migratedRoot, dryRun: false)
try require(repeatedMigration.skippedCount == 1, "Migration was not idempotent")

let markdownFixture = """
---
tags: [swift, notes]
---
# Heading

- [x] Task

> [!TIP] Read this
> [[Folder/Note#Section|Alias]] and ![[asset.png]]

| A | B |
| --- | ---: |
| 1 | 2 |
"""
let markdownDocument = MarkdownParser().parse(markdownFixture)
try require(markdownDocument.frontmatter?.properties["tags"] == .array([.string("swift"), .string("notes")]), "YAML parse failed")
let extractedLinks = MarkdownLinkExtractor().extract(from: markdownDocument)
try require(extractedLinks.contains { $0.kind == .wikilink && $0.destination == "Folder/Note" && $0.heading == "Section" }, "Wikilink extraction failed")
try require(extractedLinks.contains { $0.kind == .embed && $0.destination == "asset.png" }, "Embed extraction failed")
let renderedHTML = MarkdownRenderer().renderHTML(markdownDocument)
try require(renderedHTML.contains("<table>"), "Table rendering failed")
try require(renderedHTML.contains("callout-tip"), "Callout rendering failed")
let screenshotTableFixture = """
| Column 1 | Column 2 | Column 3 |
| --- | --- | --- |
|  |  |  |

| Столбец 1 | Столбец 2 | Столбец 3 |
| --- | --- | --- |
|  |  |  |
"""
let screenshotTables = MarkdownParser().parse(screenshotTableFixture).blocks.filter {
    if case .table = $0.kind { return true }
    return false
}
try require(screenshotTables.count == 2, "Screenshot-style Markdown tables were not parsed as visual tables")

let interactiveEditor = MarkdownInteractiveEditor()
let taskFixture = "Задачи 😀\n- [ ] Первая\n  - [X] Вложенная\n+ [ ]\n"
let interactiveTasks = interactiveEditor.tasks(in: taskFixture)
try require(interactiveTasks.count == 3, "Interactive task scanning failed")
let emptyTaskDocument = MarkdownParser().parse("- [ ]\n- [x]\n")
guard case .list(let emptyTaskList) = emptyTaskDocument.blocks.first?.kind else {
    throw SmokeFailure.assertion("Empty task labels were not parsed as a list")
}
try require(emptyTaskList.items.map(\.task) == [.unchecked, .checked], "Empty task labels were not parsed as tasks")
let toggledTaskFixture = interactiveEditor.togglingTask(in: taskFixture, occurrence: interactiveTasks[0])
try require(toggledTaskFixture.contains("- [x] Первая"), "Interactive task toggle failed")
try require(toggledTaskFixture.contains("  - [X] Вложенная"), "Task toggle changed an unrelated task")

let tableFixture = "До\n\n| A | B |\n| :--- | ---: |\n| 1 | 2 |\n\nПосле"
let tableLocation = (tableFixture as NSString).range(of: "| A | B |").location
guard let editableTable = interactiveEditor.table(in: tableFixture, nearUTF16Location: tableLocation) else {
    throw SmokeFailure.assertion("Interactive table lookup failed")
}
var tableDraft = editableTable.draft
tableDraft.insertColumn(at: 1)
tableDraft.cells[0][1] = "Статус"
tableDraft.cells[1][1] = "Готово"
tableDraft.alignments[1] = .center
let editedTableFixture = interactiveEditor.replacingTable(in: tableFixture, context: editableTable, with: tableDraft)
try require(editedTableFixture.contains("| A | Статус | B |"), "Interactive table column insertion failed")
try require(editedTableFixture.contains("| :--- | :---: | ---: |"), "Interactive table alignment failed")
try require(interactiveEditor.table(in: tableFixture, nearUTF16Location: 0) == nil, "Table lookup ignored the cursor")
let insertedTable = interactiveEditor.newTable(
    in: "ТекстПродолжение",
    replacingUTF16Range: NSRange(location: 5, length: 0),
    rows: 2,
    columns: 2
)
let tableInsertedIntoText = interactiveEditor.replacingTable(
    in: "ТекстПродолжение",
    context: insertedTable,
    with: insertedTable.draft
)
try require(tableInsertedIntoText.contains("Текст\n\n| Column 1 | Column 2 |"), "New table lacks a leading Markdown block boundary")
try require(tableInsertedIntoText.contains("| --- | --- |\n|  |  |\n\nПродолжение"), "New table lacks a trailing Markdown block boundary")

let attachmentNotePath = try service.createNote(in: .root, preferredName: "Attachment Note", markdown: "")
var attachmentSettings = VaultSettings()
attachmentSettings.attachmentLocation = .subfolder
attachmentSettings.attachmentSubfolderName = "assets"
let attachmentService = try AttachmentService(vaultURL: root)
let attachmentPath = try attachmentService.save(
    data: Data([0x89, 0x50, 0x4E, 0x47]),
    preferredName: "diagram.png",
    for: attachmentNotePath,
    settings: attachmentSettings
)
let embed = attachmentService.embedMarkdown(for: attachmentPath, from: attachmentNotePath, width: 480)
let attachmentNote = try service.readNote(at: attachmentNotePath)
_ = try service.writeNote(at: attachmentNotePath, markdown: embed, expectedRevision: attachmentNote.revision)
let attachmentAudit = try attachmentService.audit()
try require(attachmentAudit.missingReferences.isEmpty, "Attachment audit reported a valid embed as missing")
try require(attachmentAudit.unusedAttachments.isEmpty, "Attachment audit reported a used file as unused")

print("NotesCore vault smoke test passed")
