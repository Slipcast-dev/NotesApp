import Foundation

public struct MarkdownParser {
    public init() {}

    public func parse(_ source: String) -> MarkdownDocument {
        let lines = sourceLines(source)
        var startIndex = 0
        var frontmatter: YAMLFrontmatter?
        if lines.first?.text.trimmingCharacters(in: .whitespaces) == "---",
           let closing = lines.dropFirst().firstIndex(where: { $0.text.trimmingCharacters(in: .whitespaces) == "---" }) {
            let raw = lines[1..<closing].map(\.text).joined(separator: "\n")
            frontmatter = parseFrontmatter(raw)
            startIndex = closing + 1
        }
        let blocks = parseBlocks(Array(lines.dropFirst(startIndex)))
        return MarkdownDocument(frontmatter: frontmatter, blocks: blocks, source: source)
    }

    public func parseInlines(_ source: String, sourceOffset: Int = 0) -> [MarkdownInline] {
        InlineParser(source: source, sourceOffset: sourceOffset).parse()
    }

    private func parseBlocks(_ lines: [SourceLine]) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { index += 1; continue }

            if let fence = fenceMarker(trimmed) {
                let opening = trimmed
                let info = String(opening.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                var cursor = index + 1
                while cursor < lines.count, !lines[cursor].text.trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[cursor].text)
                    cursor += 1
                }
                let end = cursor < lines.count ? cursor : max(index, cursor - 1)
                blocks.append(block(
                    .fencedCode(language: info.isEmpty ? nil : info, code: code.joined(separator: "\n")),
                    lines: lines, start: index, end: end
                ))
                index = min(lines.count, cursor + 1)
                continue
            }

            if trimmed == "$$" {
                var math: [String] = []
                var cursor = index + 1
                while cursor < lines.count, lines[cursor].text.trimmingCharacters(in: .whitespaces) != "$$" {
                    math.append(lines[cursor].text)
                    cursor += 1
                }
                let end = cursor < lines.count ? cursor : max(index, cursor - 1)
                blocks.append(block(.math(math.joined(separator: "\n")), lines: lines, start: index, end: end))
                index = min(lines.count, cursor + 1)
                continue
            }

            if trimmed.hasPrefix("%%") {
                var comment = trimmed
                var cursor = index
                while !comment.dropFirst(2).contains("%%"), cursor + 1 < lines.count {
                    cursor += 1
                    comment += "\n" + lines[cursor].text
                }
                let value = comment.hasSuffix("%%") ? String(comment.dropFirst(2).dropLast(2)) : String(comment.dropFirst(2))
                blocks.append(block(.comment(value), lines: lines, start: index, end: cursor))
                index = cursor + 1
                continue
            }

            if let heading = headingContent(trimmed) {
                let extracted = extractBlockID(heading.text)
                blocks.append(MarkdownBlock(
                    kind: .heading(level: heading.level, content: parseInlines(extracted.text, sourceOffset: line.start)),
                    range: MarkdownSourceRange(line.start, line.end),
                    blockID: extracted.blockID
                ))
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                blocks.append(block(.horizontalRule, lines: lines, start: index, end: index))
                index += 1
                continue
            }

            if let footnote = footnoteDefinition(trimmed) {
                var content = [footnote.content]
                var cursor = index + 1
                while cursor < lines.count {
                    let next = lines[cursor].text
                    guard next.hasPrefix("  ") || next.hasPrefix("\t") else { break }
                    content.append(next.trimmingCharacters(in: .whitespaces))
                    cursor += 1
                }
                let childSource = content.joined(separator: "\n")
                blocks.append(block(
                    .footnoteDefinition(label: footnote.label, blocks: parse(childSource).blocks),
                    lines: lines, start: index, end: max(index, cursor - 1)
                ))
                index = cursor
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                var cursor = index
                while cursor < lines.count {
                    let candidate = lines[cursor].text.trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    var value = String(candidate.dropFirst())
                    if value.hasPrefix(" ") { value.removeFirst() }
                    quoteLines.append(value)
                    cursor += 1
                }
                if let callout = parseCallout(quoteLines) {
                    blocks.append(block(.callout(callout), lines: lines, start: index, end: cursor - 1))
                } else {
                    blocks.append(block(
                        .blockquote(parse(quoteLines.joined(separator: "\n")).blocks),
                        lines: lines, start: index, end: cursor - 1
                    ))
                }
                index = cursor
                continue
            }

            if index + 1 < lines.count, isTableDelimiter(lines[index + 1].text), trimmed.contains("|") {
                let headerCells = splitTableRow(line.text).map { parseInlines($0, sourceOffset: line.start) }
                let alignmentCells = splitTableRow(lines[index + 1].text)
                let alignments = alignmentCells.map(tableAlignment)
                var rows: [[[MarkdownInline]]] = []
                var cursor = index + 2
                while cursor < lines.count, lines[cursor].text.contains("|"), !lines[cursor].text.trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(splitTableRow(lines[cursor].text).map { parseInlines($0, sourceOffset: lines[cursor].start) })
                    cursor += 1
                }
                blocks.append(block(
                    .table(MarkdownTable(header: headerCells, alignments: alignments, rows: rows)),
                    lines: lines, start: index, end: cursor - 1
                ))
                index = cursor
                continue
            }

            if let marker = listMarker(line.text) {
                let parsed = parseList(lines: lines, start: index, firstMarker: marker)
                blocks.append(block(.list(parsed.list), lines: lines, start: index, end: parsed.endIndex))
                index = parsed.endIndex + 1
                continue
            }

            if line.text.hasPrefix("    ") || line.text.hasPrefix("\t") {
                var code: [String] = []
                var cursor = index
                while cursor < lines.count {
                    let value = lines[cursor].text
                    guard value.hasPrefix("    ") || value.hasPrefix("\t") || value.isEmpty else { break }
                    code.append(value.hasPrefix("    ") ? String(value.dropFirst(4)) : String(value.dropFirst()))
                    cursor += 1
                }
                blocks.append(block(.fencedCode(language: nil, code: code.joined(separator: "\n")), lines: lines, start: index, end: cursor - 1))
                index = cursor
                continue
            }

            var paragraphLines = [line.text]
            var cursor = index + 1
            while cursor < lines.count {
                let next = lines[cursor].text
                if next.trimmingCharacters(in: .whitespaces).isEmpty || isBlockStart(next) { break }
                if cursor + 1 < lines.count, isTableDelimiter(lines[cursor + 1].text), next.contains("|") { break }
                paragraphLines.append(next)
                cursor += 1
            }
            let extracted = extractBlockID(paragraphLines.joined(separator: "\n"))
            blocks.append(MarkdownBlock(
                kind: .paragraph(parseInlines(extracted.text, sourceOffset: line.start)),
                range: MarkdownSourceRange(line.start, lines[max(index, cursor - 1)].end),
                blockID: extracted.blockID
            ))
            index = cursor
        }
        return blocks
    }

    private func parseList(lines: [SourceLine], start: Int, firstMarker: ListMarker) -> (list: MarkdownList, endIndex: Int) {
        var items: [MarkdownListItem] = []
        var index = start
        var lastConsumed = start
        while index < lines.count, let marker = listMarker(lines[index].text),
              marker.indent == firstMarker.indent, marker.isOrdered == firstMarker.isOrdered {
            var itemLines = [marker.content]
            var cursor = index + 1
            while cursor < lines.count {
                if lines[cursor].text.trimmingCharacters(in: .whitespaces).isEmpty {
                    itemLines.append("")
                    cursor += 1
                    continue
                }
                if let nextMarker = listMarker(lines[cursor].text), nextMarker.indent <= firstMarker.indent { break }
                let continuationIndent = lines[cursor].text.prefix { $0 == " " }.count
                if continuationIndent <= firstMarker.indent, !lines[cursor].text.hasPrefix("\t") { break }
                let removeCount = min(lines[cursor].text.count, firstMarker.indent + 2)
                itemLines.append(String(lines[cursor].text.dropFirst(removeCount)))
                cursor += 1
            }

            var task: MarkdownTaskState?
            if itemLines[0] == "[ ]" || itemLines[0].hasPrefix("[ ] ") {
                task = .unchecked
                itemLines[0] = String(itemLines[0].dropFirst(min(4, itemLines[0].count)))
            } else if itemLines[0].lowercased() == "[x]" || itemLines[0].lowercased().hasPrefix("[x] ") {
                task = .checked
                itemLines[0] = String(itemLines[0].dropFirst(min(4, itemLines[0].count)))
            }
            let itemSource = itemLines.joined(separator: "\n")
            var itemBlocks = parse(itemSource).blocks
            if itemBlocks.isEmpty {
                itemBlocks = [MarkdownBlock(kind: .paragraph([]), range: MarkdownSourceRange(0, 0))]
            }
            items.append(MarkdownListItem(task: task, blocks: itemBlocks))
            lastConsumed = max(index, cursor - 1)
            index = cursor
        }
        let kind: MarkdownListKind = firstMarker.isOrdered
            ? .ordered(start: firstMarker.number ?? 1, delimiter: firstMarker.marker)
            : .unordered(marker: firstMarker.marker)
        return (MarkdownList(kind: kind, items: items), lastConsumed)
    }

    private func parseCallout(_ lines: [String]) -> MarkdownCallout? {
        guard let first = lines.first, first.hasPrefix("[!"), let close = first.firstIndex(of: "]") else { return nil }
        let typeStart = first.index(first.startIndex, offsetBy: 2)
        let type = String(first[typeStart..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !type.isEmpty else { return nil }
        var remainder = String(first[first.index(after: close)...])
        var foldable = false
        var expanded = true
        if remainder.hasPrefix("+") || remainder.hasPrefix("-") {
            foldable = true
            expanded = remainder.hasPrefix("+")
            remainder.removeFirst()
        }
        let title = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = lines.dropFirst().joined(separator: "\n")
        return MarkdownCallout(
            type: type.lowercased(),
            title: title.isEmpty ? nil : title,
            isFoldable: foldable,
            isInitiallyExpanded: expanded,
            blocks: parse(body).blocks
        )
    }

    private func sourceLines(_ source: String) -> [SourceLine] {
        let string = source as NSString
        var result: [SourceLine] = []
        var location = 0
        while location < string.length {
            let range = string.lineRange(for: NSRange(location: location, length: 0))
            var text = string.substring(with: range)
            if text.hasSuffix("\r\n") { text.removeLast(2) }
            else if text.hasSuffix("\n") || text.hasSuffix("\r") { text.removeLast() }
            result.append(SourceLine(text: text, start: range.location, end: NSMaxRange(range)))
            location = NSMaxRange(range)
        }
        if source.isEmpty { return [] }
        return result
    }

    private func block(_ kind: MarkdownBlockKind, lines: [SourceLine], start: Int, end: Int) -> MarkdownBlock {
        MarkdownBlock(kind: kind, range: MarkdownSourceRange(lines[start].start, lines[end].end))
    }

    private func fenceMarker(_ value: String) -> String? {
        if value.hasPrefix("```") { return String(value.prefix { $0 == "`" }) }
        if value.hasPrefix("~~~") { return String(value.prefix { $0 == "~" }) }
        return nil
    }

    private func headingContent(_ value: String) -> (level: Int, text: String)? {
        let hashes = value.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), value.dropFirst(hashes).first == " " else { return nil }
        var text = String(value.dropFirst(hashes + 1)).trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text.removeLast(); text = text.trimmingCharacters(in: .whitespaces) }
        return (hashes, text)
    }

    private func isHorizontalRule(_ value: String) -> Bool {
        let compact = value.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first, first == "-" || first == "*" || first == "_" else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private func footnoteDefinition(_ value: String) -> (label: String, content: String)? {
        guard value.hasPrefix("[^"), let marker = value.range(of: "]: ") else { return nil }
        let label = String(value[value.index(value.startIndex, offsetBy: 2)..<marker.lowerBound])
        return (label, String(value[marker.upperBound...]))
    }

    private func listMarker(_ line: String) -> ListMarker? {
        let indent = line.prefix { $0 == " " }.count
        let value = String(line.dropFirst(indent))
        guard !value.isEmpty else { return nil }
        if let marker = value.first, ["-", "+", "*"].contains(marker), value.dropFirst().first == " " {
            return ListMarker(indent: indent, isOrdered: false, number: nil, marker: marker, content: String(value.dropFirst(2)))
        }
        let digits = value.prefix { $0.isNumber }
        guard !digits.isEmpty, let delimiter = value.dropFirst(digits.count).first,
              delimiter == "." || delimiter == ")",
              value.dropFirst(digits.count + 1).first == " " else { return nil }
        return ListMarker(
            indent: indent,
            isOrdered: true,
            number: Int(digits),
            marker: delimiter,
            content: String(value.dropFirst(digits.count + 2))
        )
    }

    private func isBlockStart(_ line: String) -> Bool {
        let value = line.trimmingCharacters(in: .whitespaces)
        return fenceMarker(value) != nil || value == "$$" || value.hasPrefix("%%")
            || headingContent(value) != nil || isHorizontalRule(value) || footnoteDefinition(value) != nil
            || value.hasPrefix(">") || listMarker(line) != nil || line.hasPrefix("    ") || line.hasPrefix("\t")
    }

    private func isTableDelimiter(_ line: String) -> Bool {
        let cells = splitTableRow(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let value = cell.trimmingCharacters(in: .whitespaces)
            let core = value.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return core.count >= 3 && core.allSatisfy { $0 == "-" }
        }
    }

    private func splitTableRow(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in value {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
                current.append(character)
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private func tableAlignment(_ value: String) -> MarkdownTable.Alignment {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(":"), trimmed.hasSuffix(":") { return .center }
        if trimmed.hasSuffix(":") { return .right }
        if trimmed.hasPrefix(":") { return .left }
        return .none
    }

    private func extractBlockID(_ value: String) -> (text: String, blockID: String?) {
        guard let range = value.range(of: #"\s\^[A-Za-z0-9-]+\s*$"#, options: .regularExpression) else {
            return (value, nil)
        }
        let token = value[range].trimmingCharacters(in: .whitespacesAndNewlines)
        return (String(value[..<range.lowerBound]), String(token.dropFirst()))
    }

    private func parseFrontmatter(_ raw: String) -> YAMLFrontmatter {
        let lines = raw.components(separatedBy: .newlines)
        var properties: [String: YAMLValue] = [:]
        var order: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  !line.trimmingCharacters(in: .whitespaces).hasPrefix("#"),
                  let colon = line.firstIndex(of: ":") else { index += 1; continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { index += 1; continue }
            let remainder = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            order.append(key)
            if remainder.isEmpty {
                var values: [YAMLValue] = []
                var cursor = index + 1
                while cursor < lines.count {
                    let candidate = lines[cursor].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix("- ") else { break }
                    values.append(parseYAMLScalar(String(candidate.dropFirst(2))))
                    cursor += 1
                }
                properties[key] = .array(values)
                index = cursor
            } else {
                properties[key] = parseYAMLScalar(remainder)
                index += 1
            }
        }
        return YAMLFrontmatter(properties: properties, keyOrder: order, raw: raw)
    }

    private func parseYAMLScalar(_ raw: String) -> YAMLValue {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value == "null" || value == "~" { return .null }
        if value.lowercased() == "true" { return .bool(true) }
        if value.lowercased() == "false" { return .bool(false) }
        if let number = Double(value) { return .number(number) }
        if value.hasPrefix("["), value.hasSuffix("]") {
            let content = value.dropFirst().dropLast()
            return .array(content.split(separator: ",").map { parseYAMLScalar(String($0)) })
        }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return .string(String(value.dropFirst().dropLast()))
        }
        return .string(value)
    }
}

private struct SourceLine {
    let text: String
    let start: Int
    let end: Int
}

private struct ListMarker {
    let indent: Int
    let isOrdered: Bool
    let number: Int?
    let marker: Character
    let content: String
}

private struct InlineParser {
    let source: NSString
    let sourceOffset: Int

    init(source: String, sourceOffset: Int) {
        self.source = source as NSString
        self.sourceOffset = sourceOffset
    }

    func parse() -> [MarkdownInline] {
        var result: [MarkdownInline] = []
        var text = ""
        var textStart = 0
        var position = 0

        func node(_ kind: MarkdownInlineKind, _ start: Int, _ end: Int) -> MarkdownInline {
            MarkdownInline(kind: kind, range: MarkdownSourceRange(sourceOffset + start, sourceOffset + end))
        }
        func nested(_ value: String, at offset: Int) -> [MarkdownInline] {
            InlineParser(source: value, sourceOffset: sourceOffset + offset).parse()
        }
        func nextClosing(_ delimiter: String, after start: Int) -> NSRange? {
            let search = NSRange(location: start, length: source.length - start)
            let range = source.range(of: delimiter, options: [], range: search)
            return range.location == NSNotFound ? nil : range
        }
        func flush() {
            guard !text.isEmpty else { return }
            result.append(node(.text(text), textStart, position))
            text = ""
        }
        func appendText(_ value: String, at start: Int) {
            if text.isEmpty { textStart = start }
            text += value
        }

        while position < source.length {
            let remaining = source.substring(from: position)
            if remaining.hasPrefix("\\"), position + 1 < source.length {
                let nextRange = source.rangeOfComposedCharacterSequence(at: position + 1)
                appendText(source.substring(with: nextRange), at: position)
                position = NSMaxRange(nextRange)
                continue
            }

            if remaining.hasPrefix("![["), let closing = nextClosing("]]", after: position + 3) {
                flush()
                let raw = source.substring(with: NSRange(location: position + 3, length: closing.location - position - 3))
                result.append(node(.embed(parseWikiLink(raw)), position, NSMaxRange(closing)))
                position = NSMaxRange(closing)
                continue
            }
            if remaining.hasPrefix("[["), let closing = nextClosing("]]", after: position + 2) {
                flush()
                let raw = source.substring(with: NSRange(location: position + 2, length: closing.location - position - 2))
                result.append(node(.wikilink(parseWikiLink(raw)), position, NSMaxRange(closing)))
                position = NSMaxRange(closing)
                continue
            }
            if remaining.hasPrefix("%%"), let closing = nextClosing("%%", after: position + 2) {
                flush()
                let value = source.substring(with: NSRange(location: position + 2, length: closing.location - position - 2))
                result.append(node(.comment(value), position, NSMaxRange(closing)))
                position = NSMaxRange(closing)
                continue
            }
            if remaining.hasPrefix("!["), let parsed = parseMarkdownLink(at: position, image: true) {
                flush()
                result.append(node(.image(alt: parsed.label, destination: parsed.destination, title: parsed.title), position, parsed.end))
                position = parsed.end
                continue
            }
            if remaining.hasPrefix("["), let parsed = parseMarkdownLink(at: position, image: false) {
                flush()
                result.append(node(
                    .link(label: nested(parsed.label, at: position + 1), destination: parsed.destination, title: parsed.title),
                    position, parsed.end
                ))
                position = parsed.end
                continue
            }
            if remaining.hasPrefix("[^") , let close = nextClosing("]", after: position + 2) {
                flush()
                let label = source.substring(with: NSRange(location: position + 2, length: close.location - position - 2))
                result.append(node(.footnoteReference(label), position, NSMaxRange(close)))
                position = NSMaxRange(close)
                continue
            }

            let delimiters: [(String, ( [MarkdownInline]) -> MarkdownInlineKind)] = [
                ("***", MarkdownInlineKind.strongEmphasis),
                ("___", MarkdownInlineKind.strongEmphasis),
                ("**", MarkdownInlineKind.strong),
                ("__", MarkdownInlineKind.strong),
                ("~~", MarkdownInlineKind.strikethrough),
                ("==", MarkdownInlineKind.highlight),
                ("*", MarkdownInlineKind.emphasis),
                ("_", MarkdownInlineKind.emphasis)
            ]
            var matchedDelimiter = false
            for (delimiter, kind) in delimiters where remaining.hasPrefix(delimiter) {
                if let closing = nextClosing(delimiter, after: position + delimiter.utf16.count), closing.location > position + delimiter.utf16.count {
                    flush()
                    let innerStart = position + delimiter.utf16.count
                    let inner = source.substring(with: NSRange(location: innerStart, length: closing.location - innerStart))
                    result.append(node(kind(nested(inner, at: innerStart)), position, NSMaxRange(closing)))
                    position = NSMaxRange(closing)
                    matchedDelimiter = true
                    break
                }
            }
            if matchedDelimiter { continue }

            if remaining.hasPrefix("`"), let closing = nextClosing("`", after: position + 1) {
                flush()
                let value = source.substring(with: NSRange(location: position + 1, length: closing.location - position - 1))
                result.append(node(.code(value), position, NSMaxRange(closing)))
                position = NSMaxRange(closing)
                continue
            }
            if remaining.hasPrefix("$"), !remaining.hasPrefix("$$"), let closing = nextClosing("$", after: position + 1) {
                flush()
                let value = source.substring(with: NSRange(location: position + 1, length: closing.location - position - 1))
                result.append(node(.math(value), position, NSMaxRange(closing)))
                position = NSMaxRange(closing)
                continue
            }
            if remaining.hasPrefix("\n") {
                let hard = text.hasSuffix("  ")
                if hard { text.removeLast(2) }
                flush()
                result.append(node(hard ? .hardBreak : .softBreak, position, position + 1))
                position += 1
                continue
            }

            let range = source.rangeOfComposedCharacterSequence(at: position)
            appendText(source.substring(with: range), at: position)
            position = NSMaxRange(range)
        }
        flush()
        return result
    }

    private func parseWikiLink(_ raw: String) -> WikiLink {
        let aliasParts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let target = String(aliasParts[0]).trimmingCharacters(in: .whitespaces)
        let alias = aliasParts.count > 1 ? String(aliasParts[1]).trimmingCharacters(in: .whitespaces) : nil
        if let blockRange = target.range(of: "#^") {
            return WikiLink(
                notePath: String(target[..<blockRange.lowerBound]),
                blockID: String(target[blockRange.upperBound...]),
                alias: alias
            )
        }
        if let headingRange = target.range(of: "#") {
            return WikiLink(
                notePath: String(target[..<headingRange.lowerBound]),
                heading: String(target[headingRange.upperBound...]),
                alias: alias
            )
        }
        return WikiLink(notePath: target, alias: alias)
    }

    private func parseMarkdownLink(at position: Int, image: Bool) -> (label: String, destination: String, title: String?, end: Int)? {
        let labelStart = position + (image ? 2 : 1)
        let labelClose = source.range(of: "](", options: [], range: NSRange(location: labelStart, length: source.length - labelStart))
        guard labelClose.location != NSNotFound else { return nil }
        let destinationStart = NSMaxRange(labelClose)
        let close = source.range(of: ")", options: [], range: NSRange(location: destinationStart, length: source.length - destinationStart))
        guard close.location != NSNotFound else { return nil }
        let label = source.substring(with: NSRange(location: labelStart, length: labelClose.location - labelStart))
        let rawDestination = source.substring(with: NSRange(location: destinationStart, length: close.location - destinationStart))
        let parsed = splitDestination(rawDestination)
        return (label, parsed.destination, parsed.title, NSMaxRange(close))
    }

    private func splitDestination(_ raw: String) -> (destination: String, title: String?) {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard let quote = value.range(of: " \"") , value.hasSuffix("\"") else { return (value, nil) }
        return (String(value[..<quote.lowerBound]), String(value[quote.upperBound...].dropLast()))
    }
}
