import XCTest
@testable import NotesCore

final class MarkdownParserTests: XCTestCase {
    private let parser = MarkdownParser()

    func testParsesFrontmatterGFMAndVaultExtensionsIntoOneAST() throws {
        let source = """
        ---
        title: "AST fixture"
        tags:
          - work
          - swift
        rating: 4.5
        published: true
        aliases: [Fixture, Test]
        ---
        # Heading **bold** ^heading-id

        Paragraph with *italic*, ***both***, ~~strike~~, ==mark==, `code`, $x^2$ and a [site](https://example.com "Example").

        - [ ] Open task
        - [x] Done task
          - Nested item

        > [!NOTE]+ Callout title
        > Body with [[Folder/Note#Section|Alias]] and ![[Image.png]].

        | Name | Value |
        | :--- | ---: |
        | one | two |

        ```swift
        print("hello")
        ```

        $$
        E = mc^2
        $$

        [^one]: Footnote text

        Paragraph block ^block-one
        """

        let document = parser.parse(source)
        XCTAssertEqual(document.frontmatter?.properties["title"], .string("AST fixture"))
        XCTAssertEqual(document.frontmatter?.properties["tags"], .array([.string("work"), .string("swift")]))
        XCTAssertEqual(document.frontmatter?.properties["rating"], .number(4.5))
        XCTAssertEqual(document.frontmatter?.properties["published"], .bool(true))
        XCTAssertTrue(document.blocks.contains { if case .heading(level: 1, _) = $0.kind { return $0.blockID == "heading-id" }; return false })
        XCTAssertTrue(document.blocks.contains { if case .list(let list) = $0.kind { return list.items.map(\.task) == [.unchecked, .checked] }; return false })
        XCTAssertTrue(document.blocks.contains { if case .callout(let callout) = $0.kind { return callout.type == "note" && callout.isFoldable }; return false })
        XCTAssertTrue(document.blocks.contains { if case .table(let table) = $0.kind { return table.alignments == [.left, .right] }; return false })
        XCTAssertTrue(document.blocks.contains { if case .fencedCode(language: "swift", _) = $0.kind { return true }; return false })
        XCTAssertTrue(document.blocks.contains { if case .math = $0.kind { return true }; return false })
        XCTAssertTrue(document.blocks.contains { if case .footnoteDefinition(label: "one", _) = $0.kind { return true }; return false })
        XCTAssertTrue(document.blocks.contains { $0.blockID == "block-one" })

        let links = MarkdownLinkExtractor().extract(from: document)
        XCTAssertTrue(links.contains { $0.kind == .wikilink && $0.destination == "Folder/Note" && $0.heading == "Section" && $0.label == "Alias" })
        XCTAssertTrue(links.contains { $0.kind == .embed && $0.destination == "Image.png" })
        XCTAssertTrue(links.contains { $0.kind == .markdown && $0.destination == "https://example.com" })
    }

    func testGoldenHTMLRendering() {
        let source = """
        # Hello

        **Bold** and [[Note|Alias]].

        - [x] Complete
        """
        let html = MarkdownRenderer().renderHTML(parser.parse(source))
        XCTAssertEqual(html, """
        <h1>Hello</h1>
        <p><strong>Bold</strong> and <a class="wikilink" data-target="Note">Alias</a>.</p>
        <ul><li><input type="checkbox" checked disabled> <p>Complete</p></li></ul>
        """)
    }

    func testCanonicalMarkdownRoundTripPreservesMeaning() {
        let source = """
        ## Links

        [[Note#^block|Jump]] and ![Alt](image.png)\u{20}\u{20}
        next line

        > quote

        3. three
        4. four
        """
        let first = parser.parse(source)
        let canonical = MarkdownRenderer().renderMarkdown(first)
        let second = parser.parse(canonical)
        XCTAssertEqual(MarkdownRenderer().plainText(first), MarkdownRenderer().plainText(second))
        XCTAssertEqual(MarkdownLinkExtractor().extract(from: first).map(\.destination), MarkdownLinkExtractor().extract(from: second).map(\.destination))
    }

    func testCommentsAliasesHeadingLinksBlockLinksFootnotesAndEscapes() {
        let source = #"Escaped \*literal\*, %%hidden%%, [[#Local heading]], [[Note#^id]], [^ref]."#
        let document = parser.parse(source)
        let html = MarkdownRenderer().renderHTML(document)
        XCTAssertTrue(html.contains("Escaped *literal*"))
        XCTAssertFalse(html.contains("hidden"))
        let links = MarkdownLinkExtractor().extract(from: document)
        XCTAssertTrue(links.contains { $0.destination.isEmpty && $0.heading == "Local heading" })
        XCTAssertTrue(links.contains { $0.destination == "Note" && $0.blockID == "id" })
    }

    func testParsesEmptyTaskLabels() {
        let document = parser.parse("- [ ]\n- [x]\n")
        guard case .list(let list) = document.blocks.first?.kind else {
            return XCTFail("Expected a task list")
        }
        XCTAssertEqual(list.items.map(\.task), [.unchecked, .checked])
    }
}
