import Foundation
import Observation
import AppKit
import CleanCore

// MARK: - Aggregated row

/// One rendered row in the Privacy results list, representing all underlying
/// `PrivacyItem` values that share the same (kind, context) pair within a group.
/// Showing one row per pair rather than one per raw file keeps the list readable
/// even when a browser has dozens of history-related files.
struct AggregatedRow: Identifiable {
    let kind: PrivacyItemKind
    /// Profile name (e.g. "Profile 1") or Firefox profile folder name, shown as
    /// a small badge next to the row title. `nil` for the default/only profile.
    let context: String?
    /// All underlying `PrivacyItem.id` values that this row represents.
    let itemIDs: [String]
    let totalSize: Int64

    var id: String { "\(kind.rawValue)|\(context ?? "")" }
}

// MARK: - ViewModel

/// Drives the Privacy screen. Browsers and macOS recent-item lists are scanned
/// up front; each trace is selected per item. Low-impact traces (cache, history,
/// download list, recents) are pre-selected; disruptive ones (cookies → sign-
/// outs, sessions → lost tabs, site data → sign-outs) are opt-in and clearly
/// labelled, so a clean never silently signs the user out or drops their tabs.
@MainActor
@Observable
final class PrivacyViewModel {
    enum Phase: Equatable { case idle, scanning, results, cleaning, done }

    private(set) var phase: Phase = .idle
    private(set) var groups: [PrivacyGroup] = []
    /// Selected item ids (paths).
    private(set) var selected: Set<String> = []
    private(set) var lastReport: CleanReport?
    /// True when the last scan could not list `~/Library/Safari`, indicating that
    /// Full Disk Access has not been granted. Cleared at the start of each scan.
    private(set) var fdaMissing = false

    private let scanner = PrivacyScanner()
    /// Snapshot of which browsers are running. Refreshed on every scan (not just
    /// at init) so the "quit the browser first" warning reflects reality when
    /// the user actually presses Scan.
    private var runningBundleIDs: Set<String>

    init() {
        runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    /// Preloaded state for design previews (no disk access).
    init(mockGroups: [PrivacyGroup]) {
        runningBundleIDs = []
        groups = mockGroups
        selected = Set(mockGroups.flatMap { $0.items.filter(\.defaultOn).map(\.id) })
        phase = .results
    }

    // MARK: - Derived

    var totalBytes: Int64 { groups.reduce(0) { $0 + $1.totalBytes } }

    var selectedBytes: Int64 {
        groups.reduce(0) { acc, group in
            acc + group.items.reduce(0) { $0 + (selected.contains($1.id) ? $1.sizeBytes : 0) }
        }
    }

    var selectedCount: Int {
        groups.reduce(0) { acc, group in
            acc + group.items.filter { selected.contains($0.id) }.count
        }
    }

    func isRunning(_ app: PrivacyApp) -> Bool {
        !runningBundleIDs.isDisjoint(with: Set(app.bundleIDs))
    }

    /// True if the current selection includes cookies or site data (clearing them
    /// may sign the user out of websites) — surfaced in the final confirmation.
    var selectedSignsOut: Bool {
        groups.flatMap(\.items).contains { selected.contains($0.id) && $0.signsOut }
    }

    /// True if the current selection includes an open-tabs/session trace.
    var selectedLosesTabs: Bool {
        groups.flatMap(\.items).contains { selected.contains($0.id) && $0.kind == .sessions }
    }

    // MARK: - Aggregated rows

    /// Aggregated rows for one group: one row per (kind, context) pair, in
    /// encounter order, summing the sizes of all underlying items.
    func aggregatedRows(for group: PrivacyGroup) -> [AggregatedRow] {
        var seenKeys: [String] = []
        var rowMap: [String: (kind: PrivacyItemKind, context: String?, ids: [String], size: Int64)] = [:]

        for item in group.items {
            let key = "\(item.kind.rawValue)|\(item.context ?? "")"
            if rowMap[key] == nil {
                seenKeys.append(key)
                rowMap[key] = (item.kind, item.context, [], 0)
            }
            rowMap[key]!.ids.append(item.id)
            rowMap[key]!.size += item.sizeBytes
        }

        return seenKeys.compactMap { key -> AggregatedRow? in
            guard let r = rowMap[key] else { return nil }
            return AggregatedRow(kind: r.kind, context: r.context, itemIDs: r.ids, totalSize: r.size)
        }
    }

    /// Number of selected aggregated rows in one group.
    func selectedRowCount(in group: PrivacyGroup) -> Int {
        aggregatedRows(for: group).filter { isSelected(aggregatedRow: $0) }.count
    }

    /// Total number of selected aggregated rows across all groups.
    var selectedRowCount: Int {
        groups.reduce(0) { $0 + selectedRowCount(in: $1) }
    }

    func isSelected(aggregatedRow row: AggregatedRow) -> Bool {
        !row.itemIDs.isEmpty && row.itemIDs.allSatisfy { selected.contains($0) }
    }

    func toggle(aggregatedRow row: AggregatedRow) {
        let allOn = isSelected(aggregatedRow: row)
        // Mixed state → treat as off, so the first tap selects everything.
        if allOn { row.itemIDs.forEach { selected.remove($0) } }
        else      { row.itemIDs.forEach { selected.insert($0) } }
    }

    // MARK: - Selection

    func isSelected(_ id: String) -> Bool { selected.contains(id) }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func selectedCount(in group: PrivacyGroup) -> Int {
        group.items.filter { selected.contains($0.id) }.count
    }

    func selectedBytes(in group: PrivacyGroup) -> Int64 {
        group.items.reduce(0) { $0 + (selected.contains($1.id) ? $1.sizeBytes : 0) }
    }

    func toggleGroup(_ group: PrivacyGroup) {
        let ids = group.items.map(\.id)
        let allOn = !ids.isEmpty && ids.allSatisfy { selected.contains($0) }
        if allOn { ids.forEach { selected.remove($0) } }
        else { ids.forEach { selected.insert($0) } }
    }

    // MARK: - Browser control

    /// Terminate all running instances of `app` and refresh `runningBundleIDs`
    /// after a short delay so the "Running" badge clears automatically.
    func quit(_ app: PrivacyApp) {
        let bundleIDs = Set(app.bundleIDs)
        for runningApp in NSWorkspace.shared.runningApplications {
            guard let id = runningApp.bundleIdentifier, bundleIDs.contains(id) else { continue }
            runningApp.terminate()
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            runningBundleIDs = Set(
                NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
            )
        }
    }

    // MARK: - Scan / clean

    func scan() async {
        phase = .scanning
        selected = []
        lastReport = nil
        fdaMissing = false
        // Re-read running apps now — the model outlives app launch, so a browser
        // opened since then must still trigger its "quit first" warning.
        runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let engine = scanner

        let (found, fdaBlocked) = await Task.detached(priority: .userInitiated) {
            let groups = engine.scan()
            // Detect missing Full Disk Access by probing ~/Library/Safari. Without
            // FDA, contentsOfDirectory throws even though the directory exists.
            let safari = engine.libraryURL.appendingPathComponent("Safari")
            let fdaBlocked = (try? FileManager.default.contentsOfDirectory(
                at: safari, includingPropertiesForKeys: nil)) == nil
            return (groups, fdaBlocked)
        }.value

        groups = found
        fdaMissing = fdaBlocked
        // Pre-select only the low-impact defaults.
        selected = Set(found.flatMap { $0.items.filter(\.defaultOn).map(\.id) })
        phase = .results
    }

    func clean() async {
        let targets = groups.flatMap { $0.items }.filter { selected.contains($0.id) }
        guard !targets.isEmpty else { return }
        phase = .cleaning
        let engine = scanner

        let report = await Task.detached(priority: .userInitiated) {
            engine.clear(targets, dryRun: false)
        }.value

        lastReport = report
        phase = .done
    }
}
