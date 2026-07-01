import Foundation
import Observation
import CleanCore

enum CategorySelection {
    case none, some, all
}

/// Drives the Smart Scan screen. Selection is tracked per *item* (not per
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
    private(set) var lastReport: CleanReport?

    private let categories = CleanupCategory.mvpUserSafe
    private let safetyPolicy = SafetyPolicy.policy(for: CleanupCategory.mvpUserSafe)

    init() {}

    /// Preloaded state for design previews (no disk access).
    init(mockGroups: [ScanResultGroup], expandFirst: Bool = true) {
        groups = mockGroups
        selectedItems = Set(mockGroups.flatMap { $0.items.map(\.id) })
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

    func scan() async {
        phase = .scanning
        let cats = categories
        let policy = safetyPolicy

        let found = await Task.detached(priority: .userInitiated) {
            Scanner(policy: policy).scan(categories: cats)
        }.value

        // Keep only non-empty categories; show biggest items first.
        groups = found
            .filter { !$0.items.isEmpty }
            .map { ScanResultGroup(category: $0.category,
                                   items: $0.items.sorted { $0.sizeBytes > $1.sizeBytes }) }
        selectedItems = Set(groups.flatMap { $0.items.map(\.id) })
        expandedCategories = []
        lastReport = nil
        phase = .results
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
        phase = .done
    }
}
