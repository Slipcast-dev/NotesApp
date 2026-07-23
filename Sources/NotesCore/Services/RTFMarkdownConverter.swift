import AppKit
import Foundation

public struct RTFConversionResult {
    public let markdown: String
    public let warnings: [String]

    public init(markdown: String, warnings: [String]) {
        self.markdown = markdown
        self.warnings = warnings
    }
}

public enum RTFMarkdownConversionError: LocalizedError {
    case invalidRTF

    public var errorDescription: String? {
        "The legacy RTF content could not be decoded."
    }
}

public struct RTFMarkdownConverter {
    public init() {}

    public func convert(_ storedValue: String) throws -> RTFConversionResult {
        let trimmed = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{\\rtf") else {
            return RTFConversionResult(markdown: normalizePlainText(storedValue), warnings: [])
        }
        guard let data = storedValue.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
              ) else {
            throw RTFMarkdownConversionError.invalidRTF
        }

        var warnings: [String] = []
        var renderedLines: [String] = []
        let source = attributed.string as NSString
        var cursor = 0
        while cursor < source.length {
            let lineRange = source.lineRange(for: NSRange(location: cursor, length: 0))
            let contentLength = max(0, lineRange.length - newlineLength(in: source, range: lineRange))
            let contentRange = NSRange(location: lineRange.location, length: contentLength)
            renderedLines.append(renderLine(attributed, range: contentRange, warnings: &warnings))
            cursor = NSMaxRange(lineRange)
        }
        if source.length == 0 { renderedLines = [] }

        let withTables = convertBoxDrawingTables(renderedLines)
        let markdown = withTables.joined(separator: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .newlines)
        return RTFConversionResult(markdown: markdown, warnings: warnings)
    }

    private func renderLine(
        _ attributed: NSAttributedString,
        range: NSRange,
        warnings: inout [String]
    ) -> String {
        guard range.length > 0 else { return "" }
        var result = ""
        var maximumFontSize: CGFloat = 0
        var listPrefix = ""

        attributed.enumerateAttributes(in: range, options: []) { attributes, segmentRange, _ in
            var value = (attributed.string as NSString).substring(with: segmentRange)
            if attributes[.attachment] != nil {
                value = "[Attachment]"
                if !warnings.contains("An embedded RTF attachment was represented as a Markdown placeholder.") {
                    warnings.append("An embedded RTF attachment was represented as a Markdown placeholder.")
                }
            }

            let font = attributes[.font] as? NSFont
            if let font { maximumFontSize = max(maximumFontSize, font.pointSize) }
            let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
            let isBold = traits.contains(.boldFontMask)
            let isItalic = traits.contains(.italicFontMask)
            let isStruck = (attributes[.strikethroughStyle] as? Int ?? 0) != 0

            if let link = attributes[.link] {
                let destination = (link as? URL)?.absoluteString ?? String(describing: link)
                value = "[\(value)](\(destination))"
            }
            if isBold && isItalic { value = "***\(value)***" }
            else if isBold { value = "**\(value)**" }
            else if isItalic { value = "_\(value)_" }
            if isStruck { value = "~~\(value)~~" }
            result += value

            if listPrefix.isEmpty,
               let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle,
               let textList = paragraph.textLists.last {
                let indentation = String(repeating: "  ", count: max(0, paragraph.textLists.count - 1))
                listPrefix = indentation + (textList.markerFormat.rawValue.contains("decimal") ? "1. " : "- ")
            }
        }

        let plain = result.trimmingCharacters(in: .whitespaces)
        if plain.hasPrefix("☐") {
            return "- [ ] " + plain.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        if plain.hasPrefix("☑") || plain.hasPrefix("☒") {
            return "- [x] " + plain.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        if plain.hasPrefix("•") {
            return "- " + plain.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        if maximumFontSize >= 20, !plain.isEmpty {
            return "# " + plain
        }
        return listPrefix.isEmpty || plain.isEmpty ? result : listPrefix + plain
    }

    private func newlineLength(in source: NSString, range: NSRange) -> Int {
        guard range.length > 0 else { return 0 }
        let line = source.substring(with: range)
        if line.hasSuffix("\r\n") { return 2 }
        if line.hasSuffix("\n") || line.hasSuffix("\r") { return 1 }
        return 0
    }

    private func normalizePlainText(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func convertBoxDrawingTables(_ lines: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < lines.count {
            guard isTableBorder(lines[index]) else {
                result.append(lines[index])
                index += 1
                continue
            }

            var rows: [[String]] = []
            var cursor = index + 1
            while cursor < lines.count {
                let line = lines[cursor].trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("│"), line.hasSuffix("│") {
                    let cells = line.dropFirst().dropLast().split(separator: "│", omittingEmptySubsequences: false)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    rows.append(cells)
                } else if line.hasPrefix("└") {
                    cursor += 1
                    break
                } else if !isTableBorder(line) {
                    break
                }
                cursor += 1
            }

            if let header = rows.first, !header.isEmpty {
                result.append("| " + header.joined(separator: " | ") + " |")
                result.append("| " + header.map { _ in "---" }.joined(separator: " | ") + " |")
                for row in rows.dropFirst() {
                    result.append("| " + row.joined(separator: " | ") + " |")
                }
                index = cursor
            } else {
                result.append(lines[index])
                index += 1
            }
        }
        return result
    }

    private func isTableBorder(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("┌") || trimmed.hasPrefix("├") || trimmed.hasPrefix("└")
    }
}
