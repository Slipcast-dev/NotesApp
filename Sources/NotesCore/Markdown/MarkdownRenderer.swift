import Foundation

public struct MarkdownRenderer {
    public init() {}

    public func renderMarkdown(_ document: MarkdownDocument) -> String {
        var sections: [String] = []
        if let frontmatter = document.frontmatter {
            sections.append("---\n\(frontmatter.raw)\n---")
        }
        sections.append(document.blocks.map(renderBlockMarkdown).joined(separator: "\n\n"))
        return sections.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    public func renderHTML(_ document: MarkdownDocument) -> String {
        document.blocks.map(renderBlockHTML).joined(separator: "\n")
    }

    public func plainText(_ document: MarkdownDocument) -> String {
        document.blocks.map(plainText).joined(separator: "\n")
    }

    private func renderBlockMarkdown(_ block: MarkdownBlock) -> String {
        let suffix = block.blockID.map { " ^\($0)" } ?? ""
        switch block.kind {
        case .heading(let level, let content):
            return String(repeating: "#", count: level) + " " + renderInlinesMarkdown(content) + suffix
        case .paragraph(let content):
            return renderInlinesMarkdown(content) + suffix
        case .list(let list):
            return renderListMarkdown(list)
        case .blockquote(let blocks):
            return blocks.map(renderBlockMarkdown).joined(separator: "\n\n")
                .components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
        case .callout(let callout):
            let fold = callout.isFoldable ? (callout.isInitiallyExpanded ? "+" : "-") : ""
            let title = callout.title.map { " " + $0 } ?? ""
            var lines = ["> [!\(callout.type.uppercased())]\(fold)\(title)"]
            let body = callout.blocks.map(renderBlockMarkdown).joined(separator: "\n\n")
            lines += body.components(separatedBy: "\n").map { "> " + $0 }
            return lines.joined(separator: "\n")
        case .fencedCode(let language, let code):
            return "```\(language ?? "")\n\(code)\n```"
        case .table(let table):
            let header = "| " + table.header.map(renderInlinesMarkdown).joined(separator: " | ") + " |"
            let delimiter = "| " + table.alignments.map { alignment in
                switch alignment {
                case .none: return "---"
                case .left: return ":---"
                case .center: return ":---:"
                case .right: return "---:"
                }
            }.joined(separator: " | ") + " |"
            let rows = table.rows.map { "| " + $0.map(renderInlinesMarkdown).joined(separator: " | ") + " |" }
            return ([header, delimiter] + rows).joined(separator: "\n")
        case .horizontalRule:
            return "---"
        case .footnoteDefinition(let label, let blocks):
            let body = blocks.map(renderBlockMarkdown).joined(separator: "\n\n")
            let lines = body.components(separatedBy: "\n")
            guard let first = lines.first else { return "[^\(label)]:" }
            return (["[^\(label)]: \(first)"] + lines.dropFirst().map { "  " + $0 }).joined(separator: "\n")
        case .comment(let value):
            return "%%\(value)%%"
        case .math(let value):
            return "$$\n\(value)\n$$"
        }
    }

    private func renderListMarkdown(_ list: MarkdownList) -> String {
        list.items.enumerated().map { index, item in
            let marker: String
            switch list.kind {
            case .unordered(let character): marker = "\(character) "
            case .ordered(let start, let delimiter): marker = "\(start + index)\(delimiter) "
            }
            let task = item.task.map { $0 == .checked ? "[x] " : "[ ] " } ?? ""
            let body = item.blocks.map(renderBlockMarkdown).joined(separator: "\n\n")
            let lines = body.components(separatedBy: "\n")
            guard let first = lines.first else { return marker + task }
            let indentation = String(repeating: " ", count: marker.count)
            return ([marker + task + first] + lines.dropFirst().map { indentation + $0 }).joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private func renderInlinesMarkdown(_ inlines: [MarkdownInline]) -> String {
        inlines.map { inline in
            switch inline.kind {
            case .text(let value): return value
            case .emphasis(let children): return "*" + renderInlinesMarkdown(children) + "*"
            case .strong(let children): return "**" + renderInlinesMarkdown(children) + "**"
            case .strongEmphasis(let children): return "***" + renderInlinesMarkdown(children) + "***"
            case .strikethrough(let children): return "~~" + renderInlinesMarkdown(children) + "~~"
            case .highlight(let children): return "==" + renderInlinesMarkdown(children) + "=="
            case .code(let value): return "`\(value)`"
            case .link(let label, let destination, let title):
                return "[\(renderInlinesMarkdown(label))](\(destination)\(title.map { " \"\($0)\"" } ?? ""))"
            case .image(let alt, let destination, let title):
                return "![\(alt)](\(destination)\(title.map { " \"\($0)\"" } ?? ""))"
            case .wikilink(let link): return "[[\(link.target)\(link.alias.map { "|\($0)" } ?? "")]]"
            case .embed(let link): return "![[\(link.target)\(link.alias.map { "|\($0)" } ?? "")]]"
            case .math(let value): return "$\(value)$"
            case .footnoteReference(let label): return "[^\(label)]"
            case .comment(let value): return "%%\(value)%%"
            case .softBreak: return "\n"
            case .hardBreak: return "  \n"
            }
        }.joined()
    }

    private func renderBlockHTML(_ block: MarkdownBlock) -> String {
        let blockAttribute = block.blockID.map { " id=\"^\(escapeHTML($0))\"" } ?? ""
        switch block.kind {
        case .heading(let level, let content):
            return "<h\(level)\(blockAttribute)>\(renderInlinesHTML(content))</h\(level)>"
        case .paragraph(let content):
            return "<p\(blockAttribute)>\(renderInlinesHTML(content))</p>"
        case .list(let list):
            let ordered: Bool
            let opening: String
            switch list.kind {
            case .unordered: ordered = false; opening = "<ul>"
            case .ordered(let start, _): ordered = true; opening = start == 1 ? "<ol>" : "<ol start=\"\(start)\">"
            }
            let items = list.items.map { item -> String in
                let checkbox: String
                switch item.task {
                case .checked?: checkbox = "<input type=\"checkbox\" checked disabled> "
                case .unchecked?: checkbox = "<input type=\"checkbox\" disabled> "
                case nil: checkbox = ""
                }
                return "<li>\(checkbox)\(item.blocks.map(renderBlockHTML).joined())</li>"
            }.joined()
            return opening + items + (ordered ? "</ol>" : "</ul>")
        case .blockquote(let blocks):
            return "<blockquote>\(blocks.map(renderBlockHTML).joined())</blockquote>"
        case .callout(let callout):
            let title = callout.title.map { "<div class=\"callout-title\">\(escapeHTML($0))</div>" } ?? ""
            return "<aside class=\"callout callout-\(escapeHTML(callout.type))\">\(title)\(callout.blocks.map(renderBlockHTML).joined())</aside>"
        case .fencedCode(let language, let code):
            let languageClass = language.map { " class=\"language-\(escapeHTML($0))\"" } ?? ""
            return "<pre><code\(languageClass)>\(escapeHTML(code))</code></pre>"
        case .table(let table):
            let head = "<thead><tr>" + table.header.map { "<th>\(renderInlinesHTML($0))</th>" }.joined() + "</tr></thead>"
            let body = "<tbody>" + table.rows.map { row in
                "<tr>" + row.map { "<td>\(renderInlinesHTML($0))</td>" }.joined() + "</tr>"
            }.joined() + "</tbody>"
            return "<table>\(head)\(body)</table>"
        case .horizontalRule: return "<hr>"
        case .footnoteDefinition(let label, let blocks):
            return "<section class=\"footnote\" id=\"fn-\(escapeHTML(label))\">\(blocks.map(renderBlockHTML).joined())</section>"
        case .comment: return ""
        case .math(let value): return "<div class=\"math\" data-math=\"block\">\(escapeHTML(value))</div>"
        }
    }

    private func renderInlinesHTML(_ inlines: [MarkdownInline]) -> String {
        inlines.map { inline in
            switch inline.kind {
            case .text(let value): return escapeHTML(value)
            case .emphasis(let children): return "<em>\(renderInlinesHTML(children))</em>"
            case .strong(let children): return "<strong>\(renderInlinesHTML(children))</strong>"
            case .strongEmphasis(let children): return "<strong><em>\(renderInlinesHTML(children))</em></strong>"
            case .strikethrough(let children): return "<del>\(renderInlinesHTML(children))</del>"
            case .highlight(let children): return "<mark>\(renderInlinesHTML(children))</mark>"
            case .code(let value): return "<code>\(escapeHTML(value))</code>"
            case .link(let label, let destination, let title):
                let titleAttribute = title.map { " title=\"\(escapeHTML($0))\"" } ?? ""
                return "<a href=\"\(escapeHTML(destination))\"\(titleAttribute)>\(renderInlinesHTML(label))</a>"
            case .image(let alt, let destination, let title):
                let titleAttribute = title.map { " title=\"\(escapeHTML($0))\"" } ?? ""
                return "<img src=\"\(escapeHTML(destination))\" alt=\"\(escapeHTML(alt))\"\(titleAttribute)>"
            case .wikilink(let link):
                return "<a class=\"wikilink\" data-target=\"\(escapeHTML(link.target))\">\(escapeHTML(link.alias ?? link.target))</a>"
            case .embed(let link):
                return "<span class=\"embed\" data-target=\"\(escapeHTML(link.target))\">\(escapeHTML(link.alias ?? link.target))</span>"
            case .math(let value): return "<span class=\"math\" data-math=\"inline\">\(escapeHTML(value))</span>"
            case .footnoteReference(let label): return "<sup><a href=\"#fn-\(escapeHTML(label))\">\(escapeHTML(label))</a></sup>"
            case .comment: return ""
            case .softBreak: return "\n"
            case .hardBreak: return "<br>\n"
            }
        }.joined()
    }

    private func plainText(_ block: MarkdownBlock) -> String {
        switch block.kind {
        case .heading(_, let content), .paragraph(let content): return plainText(content)
        case .list(let list): return list.items.flatMap(\.blocks).map(plainText).joined(separator: "\n")
        case .blockquote(let blocks): return blocks.map(plainText).joined(separator: "\n")
        case .callout(let callout): return callout.blocks.map(plainText).joined(separator: "\n")
        case .fencedCode(_, let code), .math(let code): return code
        case .table(let table): return (table.header + table.rows.flatMap { $0 }).map(plainText).joined(separator: " ")
        case .horizontalRule, .comment: return ""
        case .footnoteDefinition(_, let blocks): return blocks.map(plainText).joined(separator: "\n")
        }
    }

    private func plainText(_ inlines: [MarkdownInline]) -> String {
        inlines.map { inline in
            switch inline.kind {
            case .text(let value), .code(let value), .math(let value): return value
            case .emphasis(let children), .strong(let children), .strongEmphasis(let children),
                    .strikethrough(let children), .highlight(let children): return plainText(children)
            case .link(let label, _, _): return plainText(label)
            case .image(let alt, _, _): return alt
            case .wikilink(let link), .embed(let link): return link.alias ?? link.target
            case .footnoteReference(let label): return label
            case .comment: return ""
            case .softBreak, .hardBreak: return "\n"
            }
        }.joined()
    }

    private func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
