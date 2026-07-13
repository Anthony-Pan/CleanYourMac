import Foundation
import Observation
import CleanCore

enum CategorySelection {
    case none, some, all
}

/// Drives the System Junk screen. Selection is tracked per *item* (not per
/// category) so the user can review and exclude individual files.
@MainActor
@Observable
final class ScanViewModel {
    enum Phase: Equatable {
        case idle, scanning, results, cleaning, done
    }

    private(set) var phase: Phase = .idle
    private(set) var groups: [ScanResultGroup] = []
    /// Item IDs (paths) currently selected for cleaning.
    private(set) var selectedItems: Set<String> = []
    /// Category IDs whose detail list is expanded.
    var expandedCategories: Set<String> = []
    /// The category whose detail screen is currently open (kept in the model so
    /// it survives sidebar switches).
    var openedCategoryID: String?
    private(set) var lastReport: CleanReport?
    /// True when the last scan was stopped before covering every location, so
    /// the results screen can say the totals are partial instead of complete.
    private(set) var wasCancelled = false

    // Live progress shown while scanning.
    private(set) var currentLocation: String = ""
    private(set) var scannedBytes: Int64 = 0
    private(set) var foundCount: Int = 0
    /// The most recently found items, for the live discovery feed.
    private(set) var recentFinds: [ScanItem] = []

    private let categories = CleanupCategory.mvpUserSafe
    private let safetyPolicy = SafetyPolicy.policy(for: CleanupCategory.mvpUserSafe)

    init() {}

    /// Preloaded state for design previews (no disk access). A couple of items
    /// in the largest group are left unticked so previews exercise the mixed
    /// checkbox state.
    init(mockGroups: [ScanResultGroup], expandFirst: Bool = true) {
        groups = mockGroups
        var selection = Set(mockGroups.flatMap { $0.items.map(\.id) })
        if let largest = mockGroups.max(by: { $0.totalBytes < $1.totalBytes }),
           largest.items.count > 3 {
            largest.items.suffix(2).forEach { selection.remove($0.id) }
        }
        selectedItems = selection
        expandedCategories = expandFirst ? Set(mockGroups.first.map { [$0.id] } ?? []) : []
        phase = .results
    }

    // MARK: - Derived totals

    var selectedBytes: Int64 {
        groups.reduce(0) { acc, group in
            acc + group.items.reduce(0) { $0 + (selectedItems.contains($1.id) ? $1.sizeBytes : 0) }
        }
    }

    var selectedItemCount: Int {
        groups.reduce(0) { acc, group in
            acc + group.items.filter { selectedItems.contains($0.id) }.count
        }
    }

    // MARK: - Per-item selection

    func isItemSelected(_ id: String) -> Bool { selectedItems.contains(id) }

    func setItem(_ id: String, _ on: Bool) {
        if on { selectedItems.insert(id) } else { selectedItems.remove(id) }
    }

    func toggleItem(_ id: String) { setItem(id, !isItemSelected(id)) }

    // MARK: - Category selection (tri-state)

    func categoryState(_ group: ScanResultGroup) -> CategorySelection {
        let selected = group.items.lazy.filter { self.selectedItems.contains($0.id) }.count
        if selected == 0 { return .none }
        if selected == group.items.count { return .all }
        return .some
    }

    func selectedCount(in group: ScanResultGroup) -> Int {
        group.items.filter { selectedItems.contains($0.id) }.count
    }

    func selectedBytes(in group: ScanResultGroup) -> Int64 {
        group.items.reduce(0) { $0 + (selectedItems.contains($1.id) ? $1.sizeBytes : 0) }
    }

    /// Tri-state checkbox mapping for a category row.
    func checkState(_ group: ScanResultGroup) -> CheckState {
        switch categoryState(group) {
        case .none: return .off
        case .some: return .mixed
        case .all:  return .on
        }
    }

    func toggleCategory(_ group: ScanResultGroup) {
        let ids = group.items.map(\.id)
        if categoryState(group) == .all {
            ids.forEach { selectedItems.remove($0) }
        } else {
            ids.forEach { selectedItems.insert($0) }
        }
    }

    // MARK: - Expansion

    func isExpanded(_ id: String) -> Bool { expandedCategories.contains(id) }

    func toggleExpanded(_ id: String) {
        if expandedCategories.contains(id) { expandedCategories.remove(id) }
        else { expandedCategories.insert(id) }
    }

    // MARK: - Scan / clean

    private var scanTask: Task<Void, Never>?

    /// Begin (or restart) a scan. Held as a task so it can be stopped; returned
    /// so an orchestrator (Smart Scan) can await completion.
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
        wasCancelled = false
        groups = []
        selectedItems = []
        expandedCategories = []
        openedCategoryID = nil
        lastReport = nil
        currentLocation = ""
        scannedBytes = 0
        foundCount = 0
        recentFinds = []

        let cats = categories
        let policy = safetyPolicy

        // Run the scan off the main actor, streaming each event back to update
        // the UI as files are discovered. Cancelling this task stops the
        // producer via `onTermination`.
        let stream = AsyncStream<CleanCore.Scanner.ScanEvent> { continuation in
            let producer = Task.detached(priority: .userInitiated) {
                CleanCore.Scanner(policy: policy).scanIncremental(categories: cats) { event in
                    if Task.isCancelled { return }
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }

        // TODO(perf): coalesce `.item` events (batch every ~32 items / 100ms).
        // The producer batching lives in Scanner.swift, which is out of this
        // unit's scope; today's cost is one main-actor hop per found item.
        for await event in stream {
            if Task.isCancelled { break }
            switch event {
            case .location(let label):
                currentLocation = label
            case .item(let item):
                scannedBytes += item.sizeBytes
                foundCount += 1
                recentFinds.append(item)
                if recentFinds.count > 5 { recentFinds.removeFirst(recentFinds.count - 5) }
            case .categoryDone(let group):
                if !group.items.isEmpty {
                    groups.append(group)
                    selectedItems.formUnion(group.items.map(\.id))
                }
            }
        }

        if Task.isCancelled {
            // Stopped early: show what was found so far, or the start screen.
            wasCancelled = true
            phase = groups.isEmpty ? .idle : .results
        } else {
            phase = .results
        }
    }

    func clean() async {
        guard !selectedItems.isEmpty else { return }
        phase = .cleaning

        let items = groups
            .flatMap { $0.items }
            .filter { selectedItems.contains($0.id) }
        let policy = safetyPolicy

        let report = await Task.detached(priority: .userInitiated) {
            Cleaner(policy: policy).clean(items, dryRun: false)
        }.value

        lastReport = report
        // Prune what actually moved to the Trash so every derived total
        // (including the Smart Scan dashboard reading these groups) reflects
        // reality; skipped/failed items stay listed.
        let trashed = Set(report.trashed)
        groups = groups.compactMap { group in
            let remaining = group.items.filter { !trashed.contains($0.id) }
            return remaining.isEmpty ? nil : ScanResultGroup(category: group.category, items: remaining)
        }
        selectedItems.subtract(trashed)
        phase = .done
    }
}

// MARK: - Scanning-screen category progress

/// State of one category while a scan runs, for the per-category status rows.
enum CategoryScanState {
    case done, active, waiting
}

extension ScanViewModel {
    /// One row per scan category, in scan order: categories already collected
    /// into `groups` are `.done` with their byte totals, the first remaining
    /// category is `.active`, and the rest are `.waiting`.
    var categoryProgress: [(id: String, name: String, state: CategoryScanState, bytes: Int64)] {
        let doneBytes = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.totalBytes) })
        var seenActive = false
        var rows: [(id: String, name: String, state: CategoryScanState, bytes: Int64)] = []
        for category in categories {
            if let bytes = doneBytes[category.id] {
                rows.append((id: category.id, name: category.nameEN, state: .done, bytes: bytes))
            } else if !seenActive {
                seenActive = true
                rows.append((id: category.id, name: category.nameEN, state: .active, bytes: 0))
            } else {
                rows.append((id: category.id, name: category.nameEN, state: .waiting, bytes: 0))
            }
        }
        return rows
    }
}
