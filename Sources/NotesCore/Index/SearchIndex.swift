import Foundation

public struct SearchResult: Identifiable, Equatable {
    public let path: NotePath
    public let title: String
    public let snippet: String
    public let score: Double

    public var id: NotePath { path }

    public init(path: NotePath, title: String, snippet: String, score: Double) {
        self.path = path
        self.title = title
        self.snippet = snippet
        self.score = score
    }
}

public enum SearchFilter: Equatable {
    case path(String)
    case file(String)
    case tag(String)
    case property(key: String, value: String?)
    case task(MarkdownTaskState)
    case block(String)
}

public struct ParsedSearchQuery: Equatable {
    public let fullTextQuery: String?
    public let regex: String?
    public let filters: [SearchFilter]

    public init(fullTextQuery: String?, regex: String?, filters: [SearchFilter]) {
        self.fullTextQuery = fullTextQuery
        self.regex = regex
        self.filters = filters
    }
}

public struct SearchQueryParser {
    public init() {}

    public func parse(_ rawQuery: String) -> ParsedSearchQuery {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/"), trimmed.hasSuffix("/"), trimmed.count > 2 {
            return ParsedSearchQuery(fullTextQuery: nil, regex: String(trimmed.dropFirst().dropLast()), filters: [])
        }
        if trimmed.lowercased().hasPrefix("regex:") {
            return ParsedSearchQuery(
                fullTextQuery: nil,
                regex: String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces),
                filters: []
            )
        }

        var terms: [String] = []
        var filters: [SearchFilter] = []
        for token in tokens(trimmed) {
            let lower = token.lowercased()
            if lower.hasPrefix("path:") { filters.append(.path(value(after: ":", in: token))) }
            else if lower.hasPrefix("file:") { filters.append(.file(value(after: ":", in: token))) }
            else if lower.hasPrefix("tag:") { filters.append(.tag(value(after: ":", in: token).trimmingCharacters(in: CharacterSet(charactersIn: "#")))) }
            else if lower.hasPrefix("property:") {
                let value = value(after: ":", in: token)
                let parts = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                filters.append(.property(key: String(parts[0]), value: parts.count > 1 ? String(parts[1]) : nil))
            } else if lower.hasPrefix("task:") {
                let value = value(after: ":", in: lower)
                filters.append(.task(["done", "checked", "x"].contains(value) ? .checked : .unchecked))
            } else if lower.hasPrefix("block:") {
                filters.append(.block(value(after: ":", in: token)))
            } else if lower.hasPrefix("line:") {
                terms.append(value(after: ":", in: token))
            } else {
                terms.append(token)
            }
        }
        let fullText = terms.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return ParsedSearchQuery(fullTextQuery: fullText.isEmpty ? nil : fullText, regex: nil, filters: filters)
    }

    private func tokens(_ query: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        for character in query {
            if character == "\"" {
                quoted.toggle()
                current.append(character)
            } else if character.isWhitespace, !quoted {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func value(after separator: Character, in token: String) -> String {
        guard let index = token.firstIndex(of: separator) else { return "" }
        var value = String(token[token.index(after: index)...])
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }
}

public actor SearchIndex {
    public let databaseURL: URL
    private let connection: SQLiteConnection
    private let queryParser = SearchQueryParser()

    public init(vaultURL: URL) throws {
        databaseURL = vaultURL.standardizedFileURL
            .appendingPathComponent(".notesapp", isDirectory: true)
            .appendingPathComponent("index.sqlite")
        connection = try SQLiteConnection(url: databaseURL)
    }

    public func search(_ query: String, limit: Int = 100) throws -> [SearchResult] {
        let parsed = queryParser.parse(query)
        if let regex = parsed.regex { return try regexSearch(regex, limit: limit) }

        var predicates: [String] = []
        var parameters: [String] = []
        if let fullText = parsed.fullTextQuery {
            predicates.append("notes_fts MATCH ?")
            parameters.append(fullText)
        }
        for filter in parsed.filters {
            switch filter {
            case .path(let value):
                predicates.append("f.path LIKE ?")
                parameters.append("%\(value)%")
            case .file(let value):
                predicates.append("f.title LIKE ?")
                parameters.append("%\(value)%")
            case .tag(let value):
                predicates.append("EXISTS (SELECT 1 FROM tags t WHERE t.path = f.path AND t.tag = ? COLLATE NOCASE)")
                parameters.append(value)
            case .property(let key, let value):
                if let value {
                    predicates.append("EXISTS (SELECT 1 FROM properties p WHERE p.path = f.path AND p.key = ? COLLATE NOCASE AND p.value LIKE ?)")
                    parameters += [key, "%\(value)%"]
                } else {
                    predicates.append("EXISTS (SELECT 1 FROM properties p WHERE p.path = f.path AND p.key = ? COLLATE NOCASE)")
                    parameters.append(key)
                }
            case .task(let state):
                predicates.append("EXISTS (SELECT 1 FROM tasks tk WHERE tk.path = f.path AND tk.state = ?)")
                parameters.append(state.rawValue)
            case .block(let value):
                predicates.append("EXISTS (SELECT 1 FROM blocks b WHERE b.path = f.path AND (b.block_id LIKE ? OR b.text LIKE ?))")
                parameters += ["%\(value)%", "%\(value)%"]
            }
        }
        let whereClause = predicates.isEmpty ? "" : "WHERE " + predicates.joined(separator: " AND ")
        let rank = parsed.fullTextQuery == nil ? "0.0" : "bm25(notes_fts)"
        let snippet = parsed.fullTextQuery == nil
            ? "substr(f.body, 1, 220)"
            : "snippet(notes_fts, 2, '<mark>', '</mark>', ' … ', 28)"
        let statement = try connection.prepare(
            "SELECT f.path, f.title, \(snippet), \(rank) FROM notes_fts f \(whereClause) ORDER BY \(rank), f.title COLLATE NOCASE LIMIT \(max(1, min(limit, 1000)));"
        )
        for (offset, parameter) in parameters.enumerated() {
            try statement.bind(parameter, at: Int32(offset + 1))
        }
        return try collectResults(statement)
    }

    private func regexSearch(_ pattern: String, limit: Int) throws -> [SearchResult] {
        let expression = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let statement = try connection.prepare("SELECT path, title, body FROM notes_fts ORDER BY title COLLATE NOCASE;")
        var results: [SearchResult] = []
        while try statement.step(), results.count < max(1, min(limit, 1000)) {
            let body = statement.string(at: 2)
            let range = NSRange(location: 0, length: (body as NSString).length)
            guard let match = expression.firstMatch(in: body, range: range) else { continue }
            let rawPath = statement.string(at: 0)
            guard let path = try? NotePath(rawPath) else { throw MetadataIndexError.invalidStoredPath(rawPath) }
            let contextRange = NSRange(
                location: max(0, match.range.location - 70),
                length: min((body as NSString).length - max(0, match.range.location - 70), match.range.length + 140)
            )
            results.append(SearchResult(
                path: path,
                title: statement.string(at: 1),
                snippet: (body as NSString).substring(with: contextRange),
                score: 0
            ))
        }
        return results
    }

    private func collectResults(_ statement: SQLiteStatement) throws -> [SearchResult] {
        var results: [SearchResult] = []
        while try statement.step() {
            let rawPath = statement.string(at: 0)
            guard let path = try? NotePath(rawPath) else { throw MetadataIndexError.invalidStoredPath(rawPath) }
            results.append(SearchResult(
                path: path,
                title: statement.string(at: 1),
                snippet: statement.string(at: 2),
                score: statement.double(at: 3)
            ))
        }
        return results
    }
}
