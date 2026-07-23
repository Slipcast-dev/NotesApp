import Foundation

public struct Vault: Identifiable, Hashable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public var id: String { rootURL.path }
    public var name: String {
        let name = rootURL.lastPathComponent
        return name.isEmpty ? rootURL.path : name
    }

    public func url(for path: NotePath) -> URL {
        guard !path.isRoot else { return rootURL }
        return path.components.reduce(rootURL) { partial, component in
            partial.appendingPathComponent(component)
        }
    }
}

public enum VaultItemKind: String, Codable {
    case folder
    case note
    case attachment
}

public struct VaultItem: Identifiable, Hashable {
    public let path: NotePath
    public let kind: VaultItemKind
    public let children: [VaultItem]
    public let modificationDate: Date?
    public let fileSize: Int64?

    public init(
        path: NotePath,
        kind: VaultItemKind,
        children: [VaultItem] = [],
        modificationDate: Date? = nil,
        fileSize: Int64? = nil
    ) {
        self.path = path
        self.kind = kind
        self.children = children
        self.modificationDate = modificationDate
        self.fileSize = fileSize
    }

    public var id: NotePath { path }
    public var name: String { path.name }
    public var displayName: String {
        kind == .note ? path.deletingPathExtension : name
    }
    public var isFolder: Bool { kind == .folder }
}

public struct VaultNoteMetadata: Identifiable, Hashable {
    public let path: NotePath
    public let createdAt: Date
    public let modifiedAt: Date
    public let fileSize: Int64

    public init(path: NotePath, createdAt: Date, modifiedAt: Date, fileSize: Int64) {
        self.path = path
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.fileSize = fileSize
    }

    public var id: NotePath { path }
    public var title: String { path.deletingPathExtension }
}

public struct VaultSnapshot {
    public let tree: [VaultItem]
    public let notes: [VaultNoteMetadata]

    public init(tree: [VaultItem], notes: [VaultNoteMetadata]) {
        self.tree = tree
        self.notes = notes
    }
}

public struct VaultRevision: Equatable {
    public let modifiedAt: Date
    public let byteCount: Int
    public let fingerprint: UInt64

    public init(modifiedAt: Date, byteCount: Int, fingerprint: UInt64) {
        self.modifiedAt = modifiedAt
        self.byteCount = byteCount
        self.fingerprint = fingerprint
    }

    public static func fingerprint(of data: Data) -> UInt64 {
        data.reduce(UInt64(14_695_981_039_346_656_037)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

public struct VaultNote {
    public let path: NotePath
    public let markdown: String
    public let revision: VaultRevision
    public let createdAt: Date

    public init(path: NotePath, markdown: String, revision: VaultRevision, createdAt: Date) {
        self.path = path
        self.markdown = markdown
        self.revision = revision
        self.createdAt = createdAt
    }

    public var title: String { path.deletingPathExtension }
}
