import Foundation

public final class StorageManager {
    public static let shared = StorageManager()

    private struct StorageLocation: Codable {
        var folderPath: String

        private enum CodingKeys: String, CodingKey {
            case folderPath = "FolderPath"
        }
    }

    public let applicationSupportDirectory: URL
    private let locationFileURL: URL

    public init(applicationSupportDirectory: URL? = nil) {
        if let applicationSupportDirectory {
            self.applicationSupportDirectory = applicationSupportDirectory
        } else {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.applicationSupportDirectory = root.appendingPathComponent("NotesApp", isDirectory: true)
        }
        locationFileURL = self.applicationSupportDirectory.appendingPathComponent("storage-location.json")
    }

    public func currentDirectory() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["NOTESAPP_DATA_DIR"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        try FileManager.default.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: locationFileURL),
           let location = try? JSONDecoder().decode(StorageLocation.self, from: data),
           !location.folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: location.folderPath, isDirectory: true).standardizedFileURL
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        let defaultDirectory = applicationSupportDirectory.appendingPathComponent("Data", isDirectory: true)
        try FileManager.default.createDirectory(at: defaultDirectory, withIntermediateDirectories: true)
        return defaultDirectory
    }

    public func setCurrentDirectory(_ directory: URL) throws {
        let normalized = directory.standardizedFileURL
        try FileManager.default.createDirectory(at: normalized, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(StorageLocation(folderPath: normalized.path))
        try data.write(to: locationFileURL, options: .atomic)
    }

    public func resetToDefaultDirectory() throws {
        if FileManager.default.fileExists(atPath: locationFileURL.path) {
            try FileManager.default.removeItem(at: locationFileURL)
        }
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
