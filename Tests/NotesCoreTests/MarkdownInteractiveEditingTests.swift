import XCTest
@testable import NotesCore

final class MarkdownInteractiveEditingTests: XCTestCase {
    private let editor = MarkdownInteractiveEditor()

    func testTaskScannerAndTogglePreserveUnicodeAndSurroundingMarkdown() throws {
        let source = "Заголовок 😀\n- [ ] Первая задача\n  * [X] Вложенная\n+ [ ]\nОбычный текст"
        let tasks = editor.tasks(in: source)

        XCTAssertEqual(tasks.map(\.text), ["Первая задача", "Вложенная", ""])
        XCTAssertEqual(tasks.map(\.state), [.unchecked, .checked, .unchecked])
        XCTAssertEqual(tasks.map(\.indentation), [0, 2, 0])

        let toggled = editor.togglingTask(in: source, occurrence: try XCTUnwrap(tasks.first))
        XCTAssertTrue(toggled.contains("- [x] Первая задача"))
        XCTAssertTrue(toggled.contains("  * [X] Вложенная"))
        XCTAssertTrue(toggled.hasPrefix("Заголовок 😀"))
    }

    func testTableDraftSupportsWordLikeRowColumnOperationsAndValidMarkdown() throws {
        let source = "Перед таблицей\n\n| Name | Value |\n| :--- | ---: |\n| one | two |\n\nПосле"
        let location = (source as NSString).range(of: "| Name").location
        let context = try XCTUnwrap(editor.table(in: source, nearUTF16Location: location))
        var draft = context.draft

        draft.insertColumn(at: 1)
        draft.cells[0][1] = "Status"
        draft.cells[1][1] = "Ready | now"
        draft.alignments[1] = .center
        draft.insertRow(at: 2)
        draft.cells[2] = ["two", "Done", "three"]
        draft.moveRow(from: 2, to: 1)

        let result = editor.replacingTable(in: source, context: context, with: draft)
        XCTAssertTrue(result.contains("| Name | Status | Value |"))
        XCTAssertTrue(result.contains("| :--- | :---: | ---: |"))
        XCTAssertTrue(result.contains("Ready \\| now"))
        XCTAssertTrue(result.hasPrefix("Перед таблицей"))
        XCTAssertTrue(result.hasSuffix("После"))

        let reparsed = MarkdownParser().parse(result)
        XCTAssertTrue(reparsed.blocks.contains { block in
            guard case .table(let table) = block.kind else { return false }
            return table.header.count == 3 && table.rows.count == 2
        })
    }

    func testTableLookupRequiresCursorInsideTableAndNewTableUsesSelection() {
        let source = "Начало\n\n| A |\n| --- |\n| B |\n"
        XCTAssertNil(editor.table(in: source, nearUTF16Location: 0))
        XCTAssertNotNil(editor.table(in: source, nearUTF16Location: (source as NSString).range(of: "| A |").location))

        let newContext = editor.newTable(atUTF16Range: NSRange(location: 3, length: 2))
        XCTAssertEqual(newContext.range, MarkdownSourceRange(3, 5))
        XCTAssertEqual(newContext.draft.rowCount, 3)
        XCTAssertEqual(newContext.draft.columnCount, 3)
    }
}
