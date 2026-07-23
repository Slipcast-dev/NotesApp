import Darwin
import Foundation

/// Recursively watches every vault directory using kqueue-backed dispatch sources.
/// Sources are rebuilt after a debounced change so newly-created folders are covered.
public final class FileChangeMonitor {
    public typealias ChangeHandler = () -> Void

    private let queue = DispatchQueue(label: "NotesApp.FileChangeMonitor", qos: .utility)
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var pendingRefresh: DispatchWorkItem?
    private var rootURL: URL?
    private var handler: ChangeHandler?
    private let excludedNames: Set<String> = [".notesapp", ".obsidian", ".git"]

    public init() {}

    deinit {
        stop()
    }

    public func start(vaultURL: URL, onChange: @escaping ChangeHandler) {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopOnQueue()
            self.rootURL = vaultURL.standardizedFileURL
            self.handler = onChange
            self.rebuildSources()
        }
    }

    public func stop() {
        queue.sync { stopOnQueue() }
    }

    private func stopOnQueue() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        sources.values.forEach { $0.cancel() }
        sources.removeAll()
        rootURL = nil
        handler = nil
    }

    private func rebuildSources() {
        guard let rootURL else { return }
        sources.values.forEach { $0.cancel() }
        sources.removeAll()

        for directory in directoryURLs(in: rootURL) {
            let descriptor = open(directory.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
                queue: queue
            )
            source.setEventHandler { [weak self] in self?.scheduleRefresh() }
            source.setCancelHandler { close(descriptor) }
            sources[directory.path] = source
            source.resume()
        }
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.rebuildSources()
            let handler = self.handler
            DispatchQueue.main.async { handler?() }
        }
        pendingRefresh = work
        queue.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func directoryURLs(in root: URL) -> [URL] {
        var result = [root]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return result }

        for case let url as URL in enumerator {
            if excludedNames.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            result.append(url)
        }
        return result
    }
}
