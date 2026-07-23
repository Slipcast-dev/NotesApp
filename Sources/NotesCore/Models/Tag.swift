import Foundation

public struct Tag: Identifiable, Hashable {
    public static let defaultColorHex = "#4C8DFF"

    public var id: Int64
    public var name: String
    public var colorHex: String

    public init(id: Int64, name: String, colorHex: String = Tag.defaultColorHex) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}
