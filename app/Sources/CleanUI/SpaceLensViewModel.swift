import Foundation
import Observation
import CleanCore

/// Drives the Space Lens screen: a read-only folder-size explorer. Scan a root,
/// rank its children by size, drill into subfolders, breadcrumb back out.
/// Nothing in this module deletes anything — it only lists, sizes and reveals.
@MainActor
@Observable
final class SpaceLensViewModel {
    enum Phase: Equatable {
        case idle, scanning, results
    }

    private(set) var phase: Phase = .idle
    /// Breadcrumb trail; first element is the scan root, last is the level shown.
    private(set) var pathStack: [URL] = []
    /// Immediate children of the current level — append order while streaming,
    /// sorted largest-first once the scan completes.
    private(set) var entries: [SpaceLensEntry] = []
    /// True when the last scan was stopped early, so totals are partial.
    private(set) var wasCancelled = false
    /// True when the current folder could not be listed (permission denied).
    private(set) var deniedCurrentFolder = false

    // Live progress shown while sizing.
    private(set) var currentChildName = ""
    private(set) var sizedBytes: Int64 = 0

    /// Results per visited folder path, so breadcrumb jumps are instant.
    private var cache: [String: [SpaceLensEntry]] = [:]
    private var scanTask: Task<Void, Never>?
    /// Bumped per scan so a superseded run never publishes stale state.
    private var scanGeneration = 0

    init() {}

    /// Preloaded results state for design previews — zero disk access. The
    /// entries become the current level of the given breadcrumb path (defaults
    /// to a single fake root).
    init(mockEntries: [SpaceLensEntry], path: [URL]? = nil) {
        let stack = path ?? [URL(fileURLWithPath: "/Users/preview")]
        pathStack = stack
        entries = mockEntries.sorted { $0.sizeBytes > $1.sizeBytes }
        if let current = stack.last { cache[current.path] = entries }
        phase = .results
    }

    // MARK: - Derived

    var totalBytes: Int64 { entries.reduce(0) { $0 + $1.sizeBytes } }

    var largestBytes: Int64 { entries.map(\.sizeBytes).max() ?? 0 }

    var currentFolderName: String { pathStack.last.map(crumbTitle) ?? "" }

    func crumbTitle(for url: URL) -> String {
        url.hasSamePath(as: FileManager.default.homeDirectoryForCurrentUser)
            ? "Home"
            : url.lastPathComponent
    }

    /// Plain directories open on click; packages and files are leaves.
    func isDrillable(_ entry: SpaceLensEntry) -> Bool {
        entry.isDirectory && !entry.isPackage
    }

    /// Share of the visible total, e.g. "42%" ("<1%" for tiny-but-real values).
    func percentOfTotal(_ entry: SpaceLensEntry) -> String {
        let total = totalBytes
        guard total > 0, entry.sizeBytes > 0 else { return "0%" }
        let pct = Double(entry.sizeBytes) / Double(total) * 100
        return pct < 1 ? "<1%" : "\(Int(pct.rounded()))%"
    }

    // MARK: - Navigation

    /// Begin (or restart) exploring from the home folder.
    func startScan() {
        pathStack = [FileManager.default.homeDirectoryForCurrentUser]
        cache = [:]
        showCurrentLevel(forceRescan: true)
    }

    /// Drill into a subfolder (cached levels appear instantly).
    func open(_ entry: SpaceLensEntry) {
        guard isDrillable(entry) else { return }
        pathStack.append(entry.url)
        showCurrentLevel()
    }

    /// Jump back to a breadcrumb (0 = the scan root).
    func jump(to index: Int) {
        guard pathStack.indices.contains(index), index < pathStack.count - 1 else { return }
        pathStack.removeSubrange((index + 1)...)
        showCurrentLevel()
    }

    /// Re-size the level currently shown (drops its cache and its descendants').
    func rescanCurrentFolder() {
        showCurrentLevel(forceRescan: true)
    }

    /// Stop an in-progress scan. Whatever was sized so far is kept.
    func cancelScan() {
        scanTask?.cancel()
    }

    private func showCurrentLevel(forceRescan: Bool = false) {
        guard let current = pathStack.last else { return }
        scanTask?.cancel()
        scanGeneration += 1

        if forceRescan {
            // Levels below the one being rescanned may have changed too.
            let prefix = current.path.hasSuffix("/") ? current.path : current.path + "/"
            cache = cache.filter { $0.key != current.path && !$0.key.hasPrefix(prefix) }
        } else if let cached = cache[current.path] {
            entries = cached
            wasCancelled = false
            deniedCurrentFolder = false
            phase = .results
            return
        }

        let generation = scanGeneration
        scanTask = Task { await runScan(of: current, generation: generation) }
    }

    private func runScan(of dir: URL, generation: Int) async {
        phase = .scanning
        wasCancelled = false
        deniedCurrentFolder = false
        entries = []
        sizedBytes = 0
        currentChildName = ""

        // Run the walk off the main actor, streaming each event back so the UI
        // shows children being sized live. Cancelling this task stops the
        // producer via `onTermination`.
        let stream = AsyncStream<SpaceLensScanner.Event> { continuation in
            let producer = Task.detached(priority: .userInitiated) {
                SpaceLensScanner().scanIncremental(root: dir) { event in
                    if Task.isCancelled { return }
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }

        var denied = false
        for await event in stream {
            guard generation == scanGeneration, !Task.isCancelled else { break }
            switch event {
            case .sizing(let name):
                currentChildName = name
            case .entry(let entry):
                entries.append(entry)
                sizedBytes += entry.sizeBytes
            case .rootUnreadable:
                denied = true
            }
        }

        // A newer scan superseded this one; its completion owns the state.
        guard generation == scanGeneration else { return }
        entries.sort { $0.sizeBytes > $1.sizeBytes }
        deniedCurrentFolder = denied
        if Task.isCancelled {
            wasCancelled = true
        } else {
            cache[dir.path] = entries
        }
        phase = .results
    }
}
