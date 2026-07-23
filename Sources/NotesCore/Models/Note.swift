import Foundation

public struct Note: Identifiable, Hashable {
    public var id: Int64
    public var title: String
    public var content: String
    public var markdownFileName: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var isPinned: Bool
    public var isDeleted: Bool
    public var tags: [Tag]

    public init(
        id: Int64,
        title: String,
        content: String,
        markdownFileName: String?,
        createdAt: Date,
        updatedAt: Date,
        isPinned: Bool,
        isDeleted: Bool,
        tags: [Tag] = []
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.markdownFileName = markdownFileName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.isDeleted = isDeleted
        self.tags = tags
    }
}
