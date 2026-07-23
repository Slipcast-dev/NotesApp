import Foundation

public enum NewNoteLocation: String, Codable, CaseIterable, Identifiable {
    case vaultRoot
    case currentFolder
    case specifiedFolder

    public var id: String { rawValue }
}

public enum AttachmentLocation: String, Codable, CaseIterable, Identifiable {
    case vaultRoot
    case sameFolder
    case subfolder
    case specifiedFolder

    public var id: String { rawValue }
}

public struct VaultSettings: Codable, Equatable {
    public var newNoteLocation: NewNoteLocation
    public var newNoteFolder: String
    public var attachmentLocation: AttachmentLocation
    public var attachmentFolder: String
    public var attachmentSubfolderName: String

    public init(
        newNoteLocation: NewNoteLocation = .currentFolder,
        newNoteFolder: String = "Notes",
        attachmentLocation: AttachmentLocation = .subfolder,
        attachmentFolder: String = "Attachments",
        attachmentSubfolderName: String = "attachments"
    ) {
        self.newNoteLocation = newNoteLocation
        self.newNoteFolder = newNoteFolder
        self.attachmentLocation = attachmentLocation
        self.attachmentFolder = attachmentFolder
        self.attachmentSubfolderName = attachmentSubfolderName
    }
}
