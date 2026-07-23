import Foundation

public enum NotePathError: LocalizedError, Equatable {
    case absolutePath
    case invalidComponent(String)

    public var errorDescription: String? {
        switch self {
        case .absolutePath:
            return "Vault path must be relative."
        case .invalidComponent(let component):
            return "Invalid vault path component: \(component)"
        }
    }
}

/// A normalized path relative to a vault root. It never contains `.` or `..`.
public struct NotePath: Hashable, Codable, Identifiable, Comparable, CustomStringConvertible {
    public let value: String

    public var id: String { value }
    public var description: String { value }
    public var isRoot: Bool { value.isEmpty }
    public var components: [String] { value.isEmpty ? [] : value.split(separator: "/").map(String.init) }
    public var name: String { components.last ?? "" }
    public var pathExtension: String { (name as NSString).pathExtension }
    public var deletingPathExtension: String { (name as NSString).deletingPathExtension }

    public static let root = NotePath(validatedValue: "")

    public init(_ rawValue: String) throws {
        let normalized = rawValue.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/") else { throw NotePathError.absolutePath }

        let rawComponents = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        for component in rawComponents {
            guard component != ".", component != "..", !component.contains("\0") else {
                throw NotePathError.invalidComponent(component)
            }
        }
        value = rawComponents.joined(separator: "/")
    }

    private init(validatedValue: String) {
        value = validatedValue
    }

    public var parent: NotePath {
        guard components.count > 1 else { return .root }
        return NotePath(validatedValue: components.dropLast().joined(separator: "/"))
    }

    public func appending(_ component: String) throws -> NotePath {
        guard !component.isEmpty, !component.contains("/"), !component.contains("\\") else {
            throw NotePathError.invalidComponent(component)
        }
        return try NotePath(isRoot ? component : "\(value)/\(component)")
    }

    public func isDescendant(of other: NotePath) -> Bool {
        guard !other.isRoot else { return !isRoot }
        return value.hasPrefix(other.value + "/")
    }

    public static func < (lhs: NotePath, rhs: NotePath) -> Bool {
        lhs.value.localizedStandardCompare(rhs.value) == .orderedAscending
    }
}
