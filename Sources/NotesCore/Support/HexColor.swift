import Foundation

public enum HexColor {
    public static func normalize(_ value: String?) -> String {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return Tag.defaultColorHex
        }

        if !value.hasPrefix("#") {
            value = "#" + value
        }

        let hex = value.dropFirst()
        guard hex.count == 6, hex.allSatisfy({ $0.isHexDigit }) else {
            return Tag.defaultColorHex
        }

        return "#" + hex.uppercased()
    }
}
