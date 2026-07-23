import Foundation

public struct MarkdownSourceRange: Codable, Hashable {
    public let lowerBound: Int
    public let upperBound: Int

    public init(_ lowerBound: Int, _ upperBound: Int) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }
}

public enum YAMLValue: Equatable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([YAMLValue])
    case object([String: YAMLValue])
}

public struct YAMLFrontmatter: Equatable, Codable {
    public let properties: [String: YAMLValue]
    public let keyOrder: [String]
    public let raw: String

    public init(properties: [String: YAMLValue], keyOrder: [String], raw: String) {
        self.properties = properties
        self.keyOrder = keyOrder
        self.raw = raw
    }
}

public struct MarkdownDocument: Equatable {
    public let frontmatter: YAMLFrontmatter?
    public let blocks: [MarkdownBlock]
    public let source: String

    public init(frontmatter: YAMLFrontmatter?, blocks: [MarkdownBlock], source: String) {
        self.frontmatter = frontmatter
        self.blocks = blocks
        self.source = source
    }
}

public struct MarkdownBlock: Equatable, Identifiable {
    public let id: UUID
    public let kind: MarkdownBlockKind
    public let range: MarkdownSourceRange
    public let blockID: String?

    public init(
        id: UUID = UUID(),
        kind: MarkdownBlockKind,
        range: MarkdownSourceRange,
        blockID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.range = range
        self.blockID = blockID
    }

    public static func == (lhs: MarkdownBlock, rhs: MarkdownBlock) -> Bool {
        lhs.kind == rhs.kind && lhs.range == rhs.range && lhs.blockID == rhs.blockID
    }
}

public indirect enum MarkdownBlockKind: Equatable {
    case heading(level: Int, content: [MarkdownInline])
    case paragraph([MarkdownInline])
    case list(MarkdownList)
    case blockquote([MarkdownBlock])
    case callout(MarkdownCallout)
    case fencedCode(language: String?, code: String)
    case table(MarkdownTable)
    case horizontalRule
    case footnoteDefinition(label: String, blocks: [MarkdownBlock])
    case comment(String)
    case math(String)
}

public enum MarkdownListKind: Equatable {
    case unordered(marker: Character)
    case ordered(start: Int, delimiter: Character)
}

public enum MarkdownTaskState: String, Codable, Equatable {
    case unchecked
    case checked
}

public struct MarkdownList: Equatable {
    public let kind: MarkdownListKind
    public let items: [MarkdownListItem]

    public init(kind: MarkdownListKind, items: [MarkdownListItem]) {
        self.kind = kind
        self.items = items
    }
}

public struct MarkdownListItem: Equatable, Identifiable {
    public let id: UUID
    public let task: MarkdownTaskState?
    public let blocks: [MarkdownBlock]

    public init(id: UUID = UUID(), task: MarkdownTaskState?, blocks: [MarkdownBlock]) {
        self.id = id
        self.task = task
        self.blocks = blocks
    }

    public static func == (lhs: MarkdownListItem, rhs: MarkdownListItem) -> Bool {
        lhs.task == rhs.task && lhs.blocks == rhs.blocks
    }
}

public struct MarkdownCallout: Equatable {
    public let type: String
    public let title: String?
    public let isFoldable: Bool
    public let isInitiallyExpanded: Bool
    public let blocks: [MarkdownBlock]

    public init(type: String, title: String?, isFoldable: Bool, isInitiallyExpanded: Bool, blocks: [MarkdownBlock]) {
        self.type = type
        self.title = title
        self.isFoldable = isFoldable
        self.isInitiallyExpanded = isInitiallyExpanded
        self.blocks = blocks
    }
}

public struct MarkdownTable: Equatable {
    public enum Alignment: String, Codable {
        case none
        case left
        case center
        case right
    }

    public let header: [[MarkdownInline]]
    public let alignments: [Alignment]
    public let rows: [[[MarkdownInline]]]

    public init(header: [[MarkdownInline]], alignments: [Alignment], rows: [[[MarkdownInline]]]) {
        self.header = header
        self.alignments = alignments
        self.rows = rows
    }
}

public struct MarkdownInline: Equatable, Identifiable {
    public let id: UUID
    public let kind: MarkdownInlineKind
    public let range: MarkdownSourceRange

    public init(id: UUID = UUID(), kind: MarkdownInlineKind, range: MarkdownSourceRange) {
        self.id = id
        self.kind = kind
        self.range = range
    }

    public static func == (lhs: MarkdownInline, rhs: MarkdownInline) -> Bool {
        lhs.kind == rhs.kind && lhs.range == rhs.range
    }
}

public indirect enum MarkdownInlineKind: Equatable {
    case text(String)
    case emphasis([MarkdownInline])
    case strong([MarkdownInline])
    case strongEmphasis([MarkdownInline])
    case strikethrough([MarkdownInline])
    case highlight([MarkdownInline])
    case code(String)
    case link(label: [MarkdownInline], destination: String, title: String?)
    case image(alt: String, destination: String, title: String?)
    case wikilink(WikiLink)
    case embed(WikiLink)
    case math(String)
    case footnoteReference(String)
    case comment(String)
    case softBreak
    case hardBreak
}

public struct WikiLink: Equatable, Codable {
    public let notePath: String
    public let heading: String?
    public let blockID: String?
    public let alias: String?

    public init(notePath: String, heading: String? = nil, blockID: String? = nil, alias: String? = nil) {
        self.notePath = notePath
        self.heading = heading
        self.blockID = blockID
        self.alias = alias
    }

    public var target: String {
        var value = notePath
        if let heading { value += "#" + heading }
        if let blockID { value += "#^" + blockID }
        return value
    }
}

public enum MarkdownSyntax {
    public static let bold = (opening: "**", closing: "**")
    public static let italic = (opening: "_", closing: "_")
    public static let strikethrough = (opening: "~~", closing: "~~")
    public static let highlight = (opening: "==", closing: "==")
    public static let wikilink = (opening: "[[", closing: "]]" )
    public static let taskUnchecked = "- [ ] "
    public static let taskChecked = "- [x] "
}
