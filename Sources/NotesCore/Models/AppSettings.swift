import Foundation

public enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    public var id: String { rawValue }
}

public enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case russian = "ru"
    case english = "en"

    public var id: String { rawValue }
}

public enum NoteSorting: String, Codable, CaseIterable, Identifiable {
    case updatedDescending = "updateddesc"
    case updatedAscending = "updatedasc"
    case titleAscending = "titleasc"
    case titleDescending = "titledesc"
    case createdDescending = "createddesc"
    case createdAscending = "createdasc"

    public var id: String { rawValue }
}

public struct AppSettings: Codable, Equatable {
    public var theme: AppTheme
    public var fontSize: Double
    public var fontFamily: String
    public var autoSave: Bool
    public var defaultSorting: NoteSorting
    public var language: AppLanguage

    public init(
        theme: AppTheme = .system,
        fontSize: Double = 14,
        fontFamily: String = "System",
        autoSave: Bool = true,
        defaultSorting: NoteSorting = .updatedDescending,
        language: AppLanguage = .russian
    ) {
        self.theme = theme
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.autoSave = autoSave
        self.defaultSorting = defaultSorting
        self.language = language
    }

    private enum CodingKeys: String, CodingKey {
        case theme = "Theme"
        case fontSize = "FontSize"
        case fontFamily = "FontFamily"
        case autoSave = "AutoSave"
        case defaultSorting = "DefaultSorting"
        case language = "Language"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 14
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? "System"
        autoSave = try container.decodeIfPresent(Bool.self, forKey: .autoSave) ?? true
        defaultSorting = try container.decodeIfPresent(NoteSorting.self, forKey: .defaultSorting) ?? .updatedDescending
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .russian
    }
}
