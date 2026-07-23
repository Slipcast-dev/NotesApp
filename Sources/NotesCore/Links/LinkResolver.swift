import Foundation

public enum LinkResolution: Equatable {
    case resolved(path: NotePath, heading: String?, blockID: String?)
    case unresolved(target: String)
    case ambiguous(target: String, candidates: [NotePath])
}

public struct LinkResolver {
    public init() {}

    public func resolve(
        _ reference: MarkdownLinkReference,
        from sourcePath: NotePath,
        candidates: [NotePath],
        aliases: [String: [NotePath]] = [:]
    ) -> LinkResolution {
        let rawTarget = reference.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawTarget.isEmpty {
            return .resolved(path: sourcePath, heading: reference.heading, blockID: reference.blockID)
        }

        let decoded = rawTarget.removingPercentEncoding ?? rawTarget
        let withoutExtension = decoded.lowercased().hasSuffix(".md") ? String(decoded.dropLast(3)) : decoded
        let normalizedTarget = normalize(withoutExtension)
        var matches: [NotePath] = []

        if decoded.contains("/") || decoded.hasPrefix(".") {
            let relativeRaw: String
            if decoded.hasPrefix("./") {
                relativeRaw = sourcePath.parent.isRoot
                    ? String(decoded.dropFirst(2))
                    : sourcePath.parent.value + "/" + String(decoded.dropFirst(2))
            } else if decoded.hasPrefix("../") {
                relativeRaw = resolveParentSegments(decoded, from: sourcePath.parent)
            } else {
                relativeRaw = decoded
            }
            let relativeWithoutExtension = relativeRaw.lowercased().hasSuffix(".md")
                ? String(relativeRaw.dropLast(3)) : relativeRaw
            matches = candidates.filter {
                normalize(pathWithoutMarkdownExtension($0)) == normalize(relativeWithoutExtension)
            }
        } else {
            matches = candidates.filter {
                normalize($0.deletingPathExtension) == normalizedTarget
                    || normalize(pathWithoutMarkdownExtension($0)) == normalizedTarget
            }
        }

        if matches.isEmpty {
            matches = aliases.first(where: { normalize($0.key) == normalizedTarget })?.value ?? []
        }
        let unique = Array(Set(matches)).sorted()
        if unique.count == 1 {
            return .resolved(path: unique[0], heading: reference.heading, blockID: reference.blockID)
        }
        if unique.count > 1 { return .ambiguous(target: rawTarget, candidates: unique) }
        return .unresolved(target: rawTarget)
    }

    private func pathWithoutMarkdownExtension(_ path: NotePath) -> String {
        let parent = path.parent.isRoot ? "" : path.parent.value + "/"
        return parent + path.deletingPathExtension
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func resolveParentSegments(_ raw: String, from parent: NotePath) -> String {
        var components = parent.components
        var remainder = raw
        while remainder.hasPrefix("../") {
            if !components.isEmpty { components.removeLast() }
            remainder = String(remainder.dropFirst(3))
        }
        if !remainder.isEmpty { components.append(remainder) }
        return components.joined(separator: "/")
    }
}
