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

    /// One bin and its scanned items, for per-bin grouping in the UI.
    struct BinSection: Identifiable {
        let bin: TrashBin
        let items: [TrashItem]
        var id: String { bin.id }
        var totalBytes: Int64 { items.totalBytes }
    }

    private(set) var phase: Phase = .idle
    /// Every bin the last scan discovered — including inaccessible ones,
    /// which the UI must surface rather than drop.
    private(set) var bins: [TrashBin] = []
    /// Items across every accessible bin, largest first.
    private(set) var items: [TrashItem] = []
    /// Item IDs (paths) currently selected for permanent removal.
    private(set) var selected: Set<String> = []
    private(set) var lastReport: TrashRemovalReport?
    /// True when the last scan was stopped before it finished, so the results
    /// are partial. Guards against reporting a cancelled scan as an empty Trash.
    private(set) var wasCancelled = false

    // Live progress shown while scanning.
    private(set) var scannedBytes: Int64 = 0
    private(set) var foundCount = 0

    /// Declarative bin discovery: the fixed rule (user Trash + per-volume
    /// `.Trashes/<uid>`) decides every root this module may delete from.
    /// Never derived from the items being deleted.
    private let discovery: TrashBinDiscovery

    init() {
        discovery = TrashBinDiscovery()
    }

    /// Preloaded results state for design snapshots — zero disk access.
    /// Everything is selected, matching the default after a real scan.
    init(mockBins: [TrashBin], mockItems: [TrashItem]) {
        discovery = TrashBinDiscovery()
        bins = mockBins
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

    /// Bins in discovery order, each with its own items (still largest first
    /// within the bin, because `items` is globally sorted).
    var sections: [BinSection] {
        bins.map { bin in
            BinSection(bin: bin, items: items.filter { $0.binID == bin.id })
        }
    }

    /// True when any bin exists that could not be listed — the UI must say
    /// so instead of presenting totals as the whole story.
    var hasInaccessibleBins: Bool {
        bins.contains { !$0.isAccessible }
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

    /// What the scan streams back: the discovered bins first, then every
    /// item as it is sized.
    private enum ScanEvent: Sendable {
        case bins([TrashBin])
        case item(TrashItem)
    }

    private func runScan() async {
        phase = .scanning
        wasCancelled = false
        bins = []
        items = []
        selected = []
        lastReport = nil
        scannedBytes = 0
        foundCount = 0

        let discovery = self.discovery

        // Discover bins and size every accessible one off the main actor,
        // streaming each item back so the live byte counter ticks up.
        let stream = AsyncStream<ScanEvent> { continuation in
            let producer = Task.detached(priority: .userInitiated) {
                let found = discovery.discoverBins()
                continuation.yield(.bins(found))
                _ = TrashScanner.scanBins(found) { item in
                    if Task.isCancelled { return }
                    continuation.yield(.item(item))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }

        var collected: [TrashItem] = []
        for await event in stream {
            if Task.isCancelled { break }
            switch event {
            case .bins(let found):
                bins = found
            case .item(let item):
                collected.append(item)
                scannedBytes += item.sizeBytes
                foundCount += 1
            }
        }

        items = collected.sorted { $0.sizeBytes > $1.sizeBytes }
        // Everything selected by default: these items were already thrown
        // away once, so the expected action is emptying all of it.
        selected = Set(items.map(\.id))

        if Task.isCancelled {
            // Stopped early. Show whatever was sized so far, or return to the
            // start screen — never the empty-Trash screen, which would falsely
            // claim the bins are empty when the scan simply didn't finish.
            wasCancelled = true
            phase = items.isEmpty ? .idle : .results
        } else {
            phase = .results
        }
    }

    // MARK: - Empty (permanent removal)

    func emptyTrash() async {
        let targets = items.filter { selected.contains($0.id) }
        guard !targets.isEmpty else { return }
        phase = .cleaning

        // Allowed roots are exactly the bins discovery's rule produced —
        // fixed before anything was selected, never widened by the targets.
        let roots = bins.map(\.root)
        let report = await Task.detached(priority: .userInitiated) {
            TrashRemover(binRoots: roots).remove(targets)
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
