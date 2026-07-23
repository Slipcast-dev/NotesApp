import Foundation

public struct MarkdownTaskOccurrence: Identifiable, Equatable {
    public let markerRange: MarkdownSourceRange
    public let lineRange: MarkdownSourceRange
    public let state: MarkdownTaskState
    public let text: String
    public let indentation: Int

    public var id: Int { markerRange.lowerBound }
}

public struct MarkdownTableDraft: Equatable {
    public var cells: [[String]]
    public var alignments: [MarkdownTable.Alignment]

    public init(cells: [[String]], alignments: [MarkdownTable.Alignment]) {
        let width = max(1, cells.map(\.count).max() ?? alignments.count)
        var normalized = cells.isEmpty ? [[String](repeating: "", count: width)] : cells
        for index in normalized.indices {
            normalized[index] += [String](repeating: "", count: max(0, width - normalized[index].count))
            if normalized[index].count > width { normalized[index] = Array(normalized[index].prefix(width)) }
        }
        self.cells = normalized
        self.alignments = alignments + [MarkdownTable.Alignment](repeating: .none, count: max(0, width - alignments.count))
        if self.alignments.count > width { self.alignments = Array(self.alignments.prefix(width)) }
    }

    public init(table: MarkdownTable) {
        let renderer = MarkdownRenderer()
        func text(_ inlines: [MarkdownInline]) -> String {
            renderer.plainText(MarkdownDocument(
                frontmatter: nil,
                blocks: [MarkdownBlock(kind: .paragraph(inlines), range: MarkdownSourceRange(0, 0))],
                source: ""
            ))
        }
        self.init(
            cells: [table.header.map(text)] + table.rows.map { $0.map(text) },
            alignments: table.alignments
        )
    }

    public var rowCount: Int { cells.count }
    public var columnCount: Int { cells.first?.count ?? 0 }

    public mutating func insertRow(at index: Int) {
        let target = min(max(0, index), rowCount)
        cells.insert([String](repeating: "", count: columnCount), at: target)
    }

    public mutating func removeRow(at index: Int) {
        guard cells.count > 1, cells.indices.contains(index) else { return }
        cells.remove(at: index)
    }

    public mutating func insertColumn(at index: Int) {
        let target = min(max(0, index), columnCount)
        for row in cells.indices { cells[row].insert("", at: target) }
        alignments.insert(.none, at: target)
    }

    public mutating func removeColumn(at index: Int) {
        guard columnCount > 1, (0..<columnCount).contains(index) else { return }
        for row in cells.indices { cells[row].remove(at: index) }
        alignments.remove(at: index)
    }

    public mutating func moveRow(from source: Int, to destination: Int) {
        guard cells.indices.contains(source), cells.indices.contains(destination), source != destination else { return }
        let row = cells.remove(at: source)
        cells.insert(row, at: destination)
    }

    public mutating func moveColumn(from source: Int, to destination: Int) {
        guard (0..<columnCount).contains(source), (0..<columnCount).contains(destination), source != destination else { return }
        for row in cells.indices {
            let value = cells[row].remove(at: source)
            cells[row].insert(value, at: destination)
        }
        let alignment = alignments.remove(at: source)
        alignments.insert(alignment, at: destination)
    }

    public func markdown() -> String {
        let header = row(cells[0])
        let delimiter = row(alignments.map { alignment in
            switch alignment {
            case .none: return "---"
            case .left: return ":---"
            case .center: return ":---:"
            case .right: return "---:"
            }
        })
        let body = cells.dropFirst().map(row)
        return ([header, delimiter] + body).joined(separator: "\n")
    }

    private func row(_ values: [String]) -> String {
        "| " + values.map(escapeCell).joined(separator: " | ") + " |"
    }

    private func escapeCell(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}

public struct MarkdownTableEditContext: Identifiable, Equatable {
    public let range: MarkdownSourceRange
    public let draft: MarkdownTableDraft
    public let leadingBoundary: String
    public let trailingBoundary: String

    public var id: Int { range.lowerBound }

    public func replacementMarkdown(with draft: MarkdownTableDraft) -> String {
        leadingBoundary + draft.markdown() + trailingBoundary
    }
}

public struct MarkdownInteractiveEditor {
    private let parser = MarkdownParser()

    public init() {}

    public func table(in markdown: String, nearUTF16Location location: Int) -> MarkdownTableEditContext? {
        let document = parser.parse(markdown)
        let tables = document.blocks.compactMap { block -> (MarkdownBlock, MarkdownTable)? in
            guard case .table(let table) = block.kind else { return nil }
            return (block, table)
        }
        guard let selected = tables.first(where: {
            location >= $0.0.range.lowerBound && location <= $0.0.range.upperBound
        }) else { return nil }
        let ns = markdown as NSString
        let range = selected.0.range
        let trailing = range.upperBound > range.lowerBound
            && range.upperBound <= ns.length
            && ns.substring(with: NSRange(location: range.upperBound - 1, length: 1)).contains("\n")
        return MarkdownTableEditContext(
            range: range,
            draft: MarkdownTableDraft(table: selected.1),
            leadingBoundary: "",
            trailingBoundary: trailing ? "\n" : ""
        )
    }

    public func newTable(
        atUTF16Range range: NSRange,
        rows: Int = 3,
        columns: Int = 3,
        headerPrefix: String = "Column"
    ) -> MarkdownTableEditContext {
        MarkdownTableEditContext(
            range: MarkdownSourceRange(range.location, NSMaxRange(range)),
            draft: MarkdownTableDraft(
                cells: (0..<max(2, rows)).map { row in
                    (0..<max(1, columns)).map { column in row == 0 ? "\(headerPrefix) \(column + 1)" : "" }
                },
                alignments: [MarkdownTable.Alignment](repeating: .none, count: max(1, columns))
            ),
            leadingBoundary: "",
            trailingBoundary: ""
        )
    }

    public func newTable(
        in markdown: String,
        replacingUTF16Range requestedRange: NSRange,
        rows: Int = 3,
        columns: Int = 3,
        headerPrefix: String = "Column"
    ) -> MarkdownTableEditContext {
        let source = markdown as NSString
        let lower = min(max(0, requestedRange.location), source.length)
        let upper = min(max(lower, NSMaxRange(requestedRange)), source.length)
        let left = source.substring(to: lower)
        let right = source.substring(from: upper)
        let leading = blockBoundary(after: left)
        let trailing = blockBoundary(before: right)
        let base = newTable(
            atUTF16Range: NSRange(location: lower, length: upper - lower),
            rows: rows,
            columns: columns,
            headerPrefix: headerPrefix
        )
        return MarkdownTableEditContext(
            range: base.range,
            draft: base.draft,
            leadingBoundary: leading,
            trailingBoundary: trailing
        )
    }

    public func replacingTable(in markdown: String, context: MarkdownTableEditContext, with draft: MarkdownTableDraft) -> String {
        let source = markdown as NSString
        let lower = min(max(0, context.range.lowerBound), source.length)
        let upper = min(max(lower, context.range.upperBound), source.length)
        let replacement = context.replacementMarkdown(with: draft)
        return source.replacingCharacters(in: NSRange(location: lower, length: upper - lower), with: replacement)
    }

    public func tasks(in markdown: String) -> [MarkdownTaskOccurrence] {
        let source = markdown as NSString
        guard let taskPattern = try? NSRegularExpression(
            pattern: #"^(?:[\t ]*>[\t ]?)*([\t ]*)[-*+][\t ]+\[([ xX])\](?:[\t ]+(.*))?$"#
        ) else { return [] }
        var result: [MarkdownTaskOccurrence] = []
        var location = 0
        var activeFence: String?
        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let line = source.substring(with: lineRange)
            let content = line.trimmingCharacters(in: .newlines)
            let trimmed = content.trimmingCharacters(in: .whitespaces)
            let fencePrefix = String(trimmed.prefix(3))
            if fencePrefix == "```" || fencePrefix == "~~~" {
                if activeFence == nil { activeFence = fencePrefix }
                else if activeFence == fencePrefix { activeFence = nil }
                location = NSMaxRange(lineRange)
                continue
            }
            let contentRange = NSRange(location: 0, length: (content as NSString).length)
            if activeFence == nil, let match = taskPattern.firstMatch(in: content, range: contentRange) {
                let stateRange = match.range(at: 2)
                let markerLocation = stateRange.location - 1
                let stateCharacter = (content as NSString).substring(with: stateRange).lowercased()
                let state: MarkdownTaskState = stateCharacter == "x" ? .checked : .unchecked
                let textRange = match.range(at: 3)
                let text = textRange.location == NSNotFound
                    ? ""
                    : (content as NSString).substring(with: textRange).trimmingCharacters(in: .whitespaces)
                result.append(MarkdownTaskOccurrence(
                    markerRange: MarkdownSourceRange(
                        lineRange.location + markerLocation,
                        lineRange.location + markerLocation + 3
                    ),
                    lineRange: MarkdownSourceRange(lineRange.location, NSMaxRange(lineRange)),
                    state: state,
                    text: text,
                    indentation: match.range(at: 1).length
                ))
            }
            location = NSMaxRange(lineRange)
        }
        return result
    }

    public func togglingTask(in markdown: String, occurrence: MarkdownTaskOccurrence) -> String {
        let source = markdown as NSString
        let range = NSRange(
            location: occurrence.markerRange.lowerBound,
            length: occurrence.markerRange.upperBound - occurrence.markerRange.lowerBound
        )
        guard NSMaxRange(range) <= source.length else { return markdown }
        return source.replacingCharacters(in: range, with: occurrence.state == .checked ? "[ ]" : "[x]")
    }

    private func blockBoundary(after left: String) -> String {
        guard !left.isEmpty else { return "" }
        if left.hasSuffix("\n\n") { return "" }
        if left.hasSuffix("\n") { return "\n" }
        return "\n\n"
    }

    private func blockBoundary(before right: String) -> String {
        guard !right.isEmpty else { return "" }
        if right.hasPrefix("\n\n") { return "" }
        if right.hasPrefix("\n") { return "\n" }
        return "\n\n"
    }
}
