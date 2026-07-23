import Foundation

public final class SettingsService {
    private let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("settings.json")
    }

    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.pretty.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }
}
