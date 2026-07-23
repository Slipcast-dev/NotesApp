import Foundation

public struct RecentVault: Codable, Identifiable, Hashable {
    public let path: String
    public let name: String
    public let bookmark: Data?
    public let lastOpenedAt: Date

    public var id: String { path }
}

public final class SecurityScopedBookmarkStore {
    private struct Registry: Codable {
        var recentVaults: [RecentVault] = []
    }

    public let registryURL: URL
    private let fileManager: FileManager

    public init(applicationSupportDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = applicationSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("NotesApp", isDirectory: true)
            ?? fileManager.temporaryDirectory.appendingPathComponent("NotesApp", isDirectory: true)
        registryURL = base.appendingPathComponent("vault-bookmarks.json")
    }

    public func save(_ url: URL) throws {
        let normalized = url.standardizedFileURL
        let bookmark = try? normalized.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        var registry = loadRegistry()
        registry.recentVaults.removeAll { $0.path == normalized.path }
        registry.recentVaults.insert(
            RecentVault(
                path: normalized.path,
                name: normalized.lastPathComponent,
                bookmark: bookmark,
                lastOpenedAt: Date()
            ),
            at: 0
        )
        if registry.recentVaults.count > 20 {
            registry.recentVaults.removeLast(registry.recentVaults.count - 20)
        }
        try writeRegistry(registry)
    }

    public func restoreLast() -> URL? {
        for recent in loadRegistry().recentVaults {
            if let resolved = resolve(recent), FileManager.default.fileExists(atPath: resolved.path) {
                return resolved
            }
        }
        return nil
    }

    public func recentVaults() -> [RecentVault] {
        loadRegistry().recentVaults
    }

    public func resolve(_ recent: RecentVault) -> URL? {
        if let bookmark = recent.bookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                if stale { try? save(url) }
                return url.standardizedFileURL
            }
        }
        return URL(fileURLWithPath: recent.path, isDirectory: true).standardizedFileURL
    }

    private func loadRegistry() -> Registry {
        guard let data = try? Data(contentsOf: registryURL),
              let registry = try? JSONDecoder().decode(Registry.self, from: data) else {
            return Registry()
        }
        return registry
    }

    private func writeRegistry(_ registry: Registry) throws {
        try fileManager.createDirectory(at: registryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(registry).write(to: registryURL, options: .atomic)
    }
}
