import Foundation
import Observation
import CleanCore

/// Drives the Trash Bins screen. Unlike every other module, removal here is
/// genuinely permanent: the items are already in the Trash, so "cleaning"
/// them is the final delete — there is no undo. Every piece of UI copy this
/// model feeds must say so.
@MainActor
@Observable
final class TrashBinsViewModel {
    enum Phase: Equatable {
        case idle, scanning, results, cleaning, done
    }

    private(set) var phase: Phase = .idle
    /// Top-level Trash items, largest first.
    private(set) var items: [TrashItem] = []
    /// Item IDs (paths) currently selected for permanent removal.
    private(set) var selected: Set<String> = []
    private(set) var lastReport: TrashRemovalReport?

    // Live progress shown while scanning.
    private(set) var scannedBytes: Int64 = 0
    private(set) var foundCount = 0

    /// Fixed declarative root, resolved once — the only location this module
    /// ever deletes from. Never derived from the items being deleted.
    private let trashRoot: URL

    init() {
        trashRoot = TrashScanner.defaultTrashRoot()
    }

    /// Preloaded results state for design snapshots — zero disk access.
    /// Everything is selected, matching the default after a real scan.
    init(mockItems: [TrashItem]) {
        trashRoot = TrashScanner.defaultTrashRoot()
        items = mockItems.sorted { $0.sizeBytes > $1.sizeBytes }
        selected = Set(mockItems.map(\.id))
        phase = .results
    }

    // MARK: - Derived totals

    var totalBytes: Int64 { items.totalBytes }

    var selectedBytes: Int64 {
        items.reduce(0) { $0 + (selected.contains($1.id) ? $1.sizeBytes : 0) }
    }

    var selectedCount: Int {
        items.filter { selected.contains($0.id) }.count
    }

    // MARK: - Selection

    func isSelected(_ id: String) -> Bool { selected.contains(id) }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    /// Tri-state for the master checkbox above the list.
    var allSelectedState: CheckState {
        if items.isEmpty || selectedCount == 0 { return .off }
        return selectedCount == items.count ? .on : .mixed
    }

    func toggleAll() {
        if selectedCount == items.count {
            selected = []
        } else {
            selected = Set(items.map(\.id))
        }
    }

    // MARK: - Scan

    private var scanTask: Task<Void, Never>?

    /// Begin (or restart) a scan. Held as a task so it can be stopped.
    @discardableResult
    func startScan() -> Task<Void, Never> {
        scanTask?.cancel()
        let task = Task { await runScan() }
        scanTask = task
        return task
    }

    /// Stop an in-progress scan. Whatever was found so far is kept.
    func cancelScan() {
        scanTask?.cancel()
    }

    private func runScan() async {
        phase = .scanning
        items = []
        selected = []
        lastReport = nil
        scannedBytes = 0
        foundCount = 0

        let root = trashRoot

        // List and size the Trash off the main actor, streaming each item back
        // so the live byte counter ticks up as folders are sized.
        let stream = AsyncStream<TrashItem> { continuation in
            let producer = Task.detached(priority: .userInitiated) {
                _ = TrashScanner(trashRoot: root).scan { item in
                    if Task.isCancelled { return }
                    continuation.yield(item)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }

        var collected: [TrashItem] = []
        for await item in stream {
            if Task.isCancelled { break }
            collected.append(item)
            scannedBytes += item.sizeBytes
            foundCount += 1
        }

        items = collected.sorted { $0.sizeBytes > $1.sizeBytes }
        // Everything selected by default: these items were already thrown
        // away once, so the expected action is emptying all of it.
        selected = Set(items.map(\.id))
        phase = .results
    }

    // MARK: - Empty (permanent removal)

    func emptyTrash() async {
        let targets = items.filter { selected.contains($0.id) }
        guard !targets.isEmpty else { return }
        phase = .cleaning

        let root = trashRoot
        let report = await Task.detached(priority: .userInitiated) {
            TrashRemover(trashRoot: root).remove(targets)
        }.value

        lastReport = report
        // Prune what was actually removed; blocked/failed items stay listed
        // so the totals on screen keep reflecting reality.
        let removed = Set(report.removed)
        items.removeAll { removed.contains($0.path) }
        selected.subtract(removed)
        phase = .done
    }
}
