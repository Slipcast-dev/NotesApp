import Foundation

public final class MarkdownNoteStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func fileName(for noteID: Int64) -> String {
        String(format: "note-%06lld.md", noteID)
    }

    public func fileURL(for note: Note) -> URL {
        directory.appendingPathComponent(note.markdownFileName ?? fileName(for: note.id))
    }

    public func write(_ note: Note) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let title = normalizedHeading(note.title)
        // CRLF keeps the file directly readable by the original Windows
        // parser; the macOS reader accepts both CRLF and LF.
        let value = "# \(title)\r\n\r\n\(note.content)"
        try value.write(to: fileURL(for: note), atomically: true, encoding: .utf8)
    }

    public func read(into note: Note) -> Note {
        let url = fileURL(for: note)
        guard let value = try? String(contentsOf: url, encoding: .utf8) else {
            return note
        }

        var result = note
        let parsed = parse(value)
        result.title = parsed.title
        result.content = parsed.content
        return result
    }

    private func parse(_ value: String) -> (title: String, content: String) {
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.hasPrefix("# "), let lineBreak = normalized.firstIndex(of: "\n") {
            let titleStart = normalized.index(normalized.startIndex, offsetBy: 2)
            let title = String(normalized[titleStart..<lineBreak]).trimmingCharacters(in: .whitespaces)
            var bodyStart = normalized.index(after: lineBreak)
            if bodyStart < normalized.endIndex, normalized[bodyStart] == "\n" {
                bodyStart = normalized.index(after: bodyStart)
            }
            return (title.isEmpty ? "Untitled" : title, String(normalized[bodyStart...]))
        }

        let title = normalized
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        return ((title?.isEmpty == false ? title! : "Untitled"), normalized)
    }

    private func normalizedHeading(_ value: String) -> String {
        let title = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled" : title
    }
}
