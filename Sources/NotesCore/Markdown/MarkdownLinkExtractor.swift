import Foundation

public enum MarkdownLinkKind: String, Codable {
    case wikilink
    case embed
    case markdown
    case image
}

public struct MarkdownLinkReference: Equatable {
    public let kind: MarkdownLinkKind
    public let destination: String
    public let label: String?
    public let heading: String?
    public let blockID: String?
    public let range: MarkdownSourceRange

    public init(
        kind: MarkdownLinkKind,
        destination: String,
        label: String?,
        heading: String?,
        blockID: String?,
        range: MarkdownSourceRange
    ) {
        self.kind = kind
        self.destination = destination
        self.label = label
        self.heading = heading
        self.blockID = blockID
        self.range = range
    }
}

public struct MarkdownLinkExtractor {
    private let renderer = MarkdownRenderer()

    public init() {}

    public func extract(from document: MarkdownDocument) -> [MarkdownLinkReference] {
        document.blocks.flatMap(extract)
    }

    private func extract(_ block: MarkdownBlock) -> [MarkdownLinkReference] {
        switch block.kind {
        case .heading(_, let inlines), .paragraph(let inlines): return extract(inlines)
        case .list(let list): return list.items.flatMap { $0.blocks.flatMap(extract) }
        case .blockquote(let blocks): return blocks.flatMap(extract)
        case .callout(let callout): return callout.blocks.flatMap(extract)
        case .table(let table): return (table.header + table.rows.flatMap { $0 }).flatMap(extract)
        case .footnoteDefinition(_, let blocks): return blocks.flatMap(extract)
        case .fencedCode, .horizontalRule, .comment, .math: return []
        }
    }

    private func extract(_ inlines: [MarkdownInline]) -> [MarkdownLinkReference] {
        inlines.flatMap { inline -> [MarkdownLinkReference] in
            switch inline.kind {
            case .wikilink(let link):
                return [MarkdownLinkReference(
                    kind: .wikilink,
                    destination: link.notePath,
                    label: link.alias,
                    heading: link.heading,
                    blockID: link.blockID,
                    range: inline.range
                )]
            case .embed(let link):
                return [MarkdownLinkReference(
                    kind: .embed,
                    destination: link.notePath,
                    label: link.alias,
                    heading: link.heading,
                    blockID: link.blockID,
                    range: inline.range
                )]
            case .link(let label, let destination, _):
                return [MarkdownLinkReference(
                    kind: .markdown,
                    destination: destination,
                    label: renderer.plainText(MarkdownDocument(frontmatter: nil, blocks: [
                        MarkdownBlock(kind: .paragraph(label), range: inline.range)
                    ], source: "")),
                    heading: nil,
                    blockID: nil,
                    range: inline.range
                )] + extract(label)
            case .image(let alt, let destination, _):
                return [MarkdownLinkReference(
                    kind: .image,
                    destination: destination,
                    label: alt,
                    heading: nil,
                    blockID: nil,
                    range: inline.range
                )]
            case .emphasis(let children), .strong(let children), .strongEmphasis(let children),
                    .strikethrough(let children), .highlight(let children):
                return extract(children)
            default:
                return []
            }
        }
    }
}
