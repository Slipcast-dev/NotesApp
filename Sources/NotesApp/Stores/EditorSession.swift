import Combine
import Foundation
import NotesCore

enum EditorMode: String, CaseIterable, Identifiable {
    case source
    case livePreview
    case reading

    var id: String { rawValue }
}

final class EditorSession: ObservableObject {
    @Published var mode: EditorMode = .livePreview
    private(set) var notePath: NotePath?
    private var selections: [NotePath: NSRange] = [:]
    private var scrollOffsets: [NotePath: Double] = [:]

    func activate(_ path: NotePath) {
        notePath = path
    }

    func remember(selection: NSRange, scrollOffset: Double, for path: NotePath) {
        selections[path] = selection
        scrollOffsets[path] = scrollOffset
    }

    func selection(for path: NotePath) -> NSRange? { selections[path] }
    func scrollOffset(for path: NotePath) -> Double? { scrollOffsets[path] }
}
