import Foundation
import UniformTypeIdentifiers

public struct AttachmentAudit: Equatable {
    public let missingReferences: [String]
    public let unusedAttachments: [NotePath]

    public init(missingReferences: [String], unusedAttachments: [NotePath]) {
        self.missingReferences = missingReferences
        self.unusedAttachments = unusedAttachments
    }
}

public final class AttachmentService {
    private let files: VaultFileService
    private let parser = MarkdownParser()
    private let extractor = MarkdownLinkExtractor()

    public init(vaultURL: URL) throws {
        files = try VaultFileService(rootURL: vaultURL)
    }

    @discardableResult
    public func importFile(
        at sourceURL: URL,
        for notePath: NotePath,
        settings: VaultSettings
    ) throws -> NotePath {
        let data = try Data(contentsOf: sourceURL)
        return try save(data: data, preferredName: sourceURL.lastPathComponent, for: notePath, settings: settings)
    }

    @discardableResult
    public func save(
        data: Data,
        preferredName: String,
        for notePath: NotePath,
        settings: VaultSettings
    ) throws -> NotePath {
        let folder = try attachmentFolder(for: notePath, settings: settings)
        try files.ensureFolder(at: folder)
        return try files.createAttachment(data: data, in: folder, preferredName: preferredName)
    }

    public func embedMarkdown(for attachment: NotePath, from notePath: NotePath, width: Int? = nil) -> String {
        let target: String
        if attachment.parent == notePath.parent {
            target = attachment.name
        } else {
            target = attachment.value
        }
        let size = width.map { "|\($0)" } ?? ""
        return "![[\(target)\(size)]]"
    }

    public func audit() throws -> AttachmentAudit {
        let snapshot = try files.snapshot()
        let attachmentPaths = Set(flatten(snapshot.tree).filter { $0.kind == .attachment }.map(\.path))
        var referenced: Set<NotePath> = []
        var missing: Set<String> = []

        for metadata in snapshot.notes {
            let note = try files.readNote(at: metadata.path)
            let links = extractor.extract(from: parser.parse(note.markdown)).filter { $0.kind == .image || $0.kind == .embed }
            for link in links {
                guard !isExternal(link.destination) else { continue }
                let destination = link.destination.components(separatedBy: "#").first ?? link.destination
                let candidates: [NotePath] = [
                    try? NotePath(destination),
                    try? NotePath(note.path.parent.isRoot ? destination : note.path.parent.value + "/" + destination)
                ].compactMap { $0 }
                if let found = candidates.first(where: { attachmentPaths.contains($0) }) {
                    referenced.insert(found)
                } else {
                    missing.insert("\(metadata.path.value): \(link.destination)")
                }
            }
        }
        return AttachmentAudit(
            missingReferences: missing.sorted(),
            unusedAttachments: attachmentPaths.subtracting(referenced).sorted()
        )
    }

    private func attachmentFolder(for notePath: NotePath, settings: VaultSettings) throws -> NotePath {
        switch settings.attachmentLocation {
        case .vaultRoot:
            return .root
        case .sameFolder:
            return notePath.parent
        case .subfolder:
            return try notePath.parent.appending(settings.attachmentSubfolderName)
        case .specifiedFolder:
            return try NotePath(settings.attachmentFolder)
        }
    }

    private func flatten(_ items: [VaultItem]) -> [VaultItem] {
        items.flatMap { [$0] + flatten($0.children) }
    }

    private func isExternal(_ value: String) -> Bool {
        guard let scheme = URL(string: value)?.scheme else { return false }
        return ["http", "https", "data", "mailto"].contains(scheme.lowercased())
    }
}
