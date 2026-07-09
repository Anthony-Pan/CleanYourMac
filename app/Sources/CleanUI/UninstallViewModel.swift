import Foundation
import Observation
import AppKit
import CleanCore

/// Drives the Uninstaller screen. Discovery is two-phase so the list appears
/// near-instantly: a metadata pass lists every app first, then real bundle
/// sizes stream in with bounded concurrency. Real sizes live in the `sizes`
/// dictionary — `InstalledApp.sizeBytes` from the fast pass is a 0 sentinel
/// the view must never render. A per-app removal plan (bundle + attributed
/// leftovers) is built lazily the first time a row is expanded. Selection is
/// tracked per leftover so the user reviews and excludes individual files
/// before anything is moved to the Trash.
@MainActor
@Observable
final class UninstallViewModel {
    enum Phase: Equatable { case idle, scanning, ready }
    enum SortOrder { case name, size }

    private(set) var phase: Phase = .idle
    private(set) var apps: [InstalledApp] = []
    var query: String = ""

    /// Real bytes per app id, filled in as the size stream yields. A missing
    /// key means "still calculating" — the view renders a shimmer, never 0 B.
    private(set) var sizes: [String: Int64] = [:]
    /// How many apps have a real size so far (drives the "Sizing i of n" copy).
    private(set) var sizedCount = 0
    /// List order. Only the user changes it — sizes landing never auto-resort.
    var sortOrder: SortOrder = .name
    private var sizingTask: Task<Void, Never>?

    /// The single app whose leftovers are currently expanded, if any.
    private(set) var expandedAppID: String?
    /// Cached plans, keyed by app id.
    private(set) var plans: [String: UninstallPlan] = [:]
    /// App ids whose plan is being computed right now.
    private(set) var planning: Set<String> = []
    /// Selected leftover ids, keyed by app id.
    private(set) var selection: [String: Set<String>] = [:]
    /// The result of the last uninstall, keyed by app id.
    private(set) var reports: [String: CleanReport] = [:]
    /// Apps that have been moved to the Trash this session.
    private(set) var removedAppIDs: Set<String> = []

    private let discovery = AppDiscovery()
    private let uninstaller = AppUninstaller()
    private let runningBundleIDs: Set<String>
    private let selfBundleID: String?

    init() {
        runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        selfBundleID = Bundle.main.bundleIdentifier
    }

    /// Preloaded state for design previews (no disk access). Mock apps carry
    /// real sizes on the model; mirror them into the streaming dictionary so
    /// previews render fully sized (no shimmer).
    init(mockApps: [InstalledApp], runningBundleIDs: Set<String> = []) {
        self.runningBundleIDs = runningBundleIDs
        selfBundleID = nil
        apps = mockApps
        sizes = Dictionary(uniqueKeysWithValues: mockApps.map { ($0.id, $0.sizeBytes) })
        sizedCount = mockApps.count
        phase = .ready
    }

    // MARK: - Derived

    /// Apps matching the search box, already-removed ones dropped, in the
    /// user-chosen order. Name order is stable while sizes stream in; size
    /// order sinks not-yet-sized apps to the bottom with a name tiebreak.
    var visibleApps: [InstalledApp] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = apps.filter { app in
            guard !removedAppIDs.contains(app.id) else { return false }
            guard !q.isEmpty else { return true }
            return app.name.lowercased().contains(q) || (app.bundleID?.lowercased().contains(q) ?? false)
        }
        switch sortOrder {
        case .name:
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            return filtered.sorted { a, b in
                let (sa, sb) = (sizes[a.id] ?? -1, sizes[b.id] ?? -1)
                guard sa == sb else { return sa > sb }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }

    /// Sum of the *known* sizes of visible apps. Pending apps contribute
    /// nothing — the bottom-bar copy says "sizing i of n" until every size is
    /// real, so a partial sum is never presented as the total.
    var totalBundleBytes: Int64 { visibleApps.reduce(0) { $0 + (sizes[$1.id] ?? 0) } }

    /// The largest known size, for the relative size bar on each row.
    var maxKnownVisibleBytes: Int64 { sizes.values.max() ?? 0 }

    /// The app's real on-disk size, or `nil` while it is still being computed
    /// (render a shimmer, never a number).
    func size(for app: InstalledApp) -> Int64? { sizes[app.id] }

    /// True while the list is visible but sizes are still streaming in.
    var isSizing: Bool { phase == .ready && sizedCount < apps.count }

    func isSelf(_ app: InstalledApp) -> Bool {
        guard let id = app.bundleID, let me = selfBundleID else { return false }
        return id == me
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        guard let id = app.bundleID else { return false }
        return runningBundleIDs.contains(id)
    }

    /// Whether we will offer an uninstall action at all. System apps and our own
    /// bundle are always refused.
    func canUninstall(_ app: InstalledApp) -> Bool { !app.isSystem && !isSelf(app) }

    // MARK: - Expansion + planning

    func isExpanded(_ app: InstalledApp) -> Bool { expandedAppID == app.id }
    func plan(for app: InstalledApp) -> UninstallPlan? { plans[app.id] }
    func isPlanning(_ app: InstalledApp) -> Bool { planning.contains(app.id) }

    func toggleExpanded(_ app: InstalledApp) {
        if expandedAppID == app.id {
            expandedAppID = nil
            return
        }
        expandedAppID = app.id
        guard canUninstall(app) else { return }
        // If a prior uninstall left a report, the cached plan is stale — rebuild
        // it against the current filesystem on re-expand.
        if reports[app.id] != nil {
            plans[app.id] = nil
            selection[app.id] = nil
            reports[app.id] = nil
        }
        guard plans[app.id] == nil, !planning.contains(app.id) else { return }
        Task { await buildPlan(for: app) }
    }

    private func buildPlan(for app: InstalledApp) async {
        planning.insert(app.id)
        let engine = uninstaller
        // The other installed apps' ids, so a leftover that belongs to a
        // separately-installed app is never attributed to this one.
        let others = Set(apps.compactMap(\.bundleID)).subtracting([app.bundleID].compactMap { $0 })
        let plan = await Task.detached(priority: .userInitiated) { engine.plan(for: app, otherAppIDs: others) }.value
        plans[app.id] = plan
        // Default-select high-confidence items only; medium (heuristic) matches
        // are opt-in so the user reviews them first.
        selection[app.id] = Set(plan.leftovers.filter { $0.confidence == .high }.map(\.id))
        planning.remove(app.id)
    }

    // MARK: - Selection

    func isSelected(_ app: InstalledApp, _ leftoverID: String) -> Bool {
        selection[app.id]?.contains(leftoverID) ?? false
    }

    func toggle(_ app: InstalledApp, _ leftoverID: String) {
        var set = selection[app.id] ?? []
        if set.contains(leftoverID) { set.remove(leftoverID) } else { set.insert(leftoverID) }
        selection[app.id] = set
    }

    func selectedIDs(for app: InstalledApp) -> Set<String> { selection[app.id] ?? [] }

    func selectedBytes(for app: InstalledApp) -> Int64 {
        guard let plan = plans[app.id] else { return 0 }
        let selected = selectedIDs(for: app)
        return plan.leftovers.reduce(0) { $0 + (selected.contains($1.id) ? $1.sizeBytes : 0) }
    }

    func selectedCount(for app: InstalledApp) -> Int { selectedIDs(for: app).count }

    func report(for app: InstalledApp) -> CleanReport? { reports[app.id] }

    /// A finished uninstall that didn't fully succeed — something was blocked by
    /// the safety gate or failed to move to the Trash. Worth surfacing to the user.
    func hasProblems(_ app: InstalledApp) -> Bool {
        guard let report = reports[app.id] else { return false }
        return !report.failed.isEmpty || !report.blocked.isEmpty
    }

    // MARK: - Scan / uninstall

    /// Two-phase discovery: list names and icons first (fast metadata pass),
    /// then stream real bundle sizes in the background.
    func scan() async {
        sizingTask?.cancel()
        phase = .scanning
        let engine = discovery
        let discovered = await Task.detached(priority: .userInitiated) { engine.discoverAppsFast() }.value
        apps = discovered
        sizes = [:]
        sizedCount = 0
        phase = .ready   // the list is visible from here; sizes stream in below
        startSizing(discovered)
    }

    /// Restart the stream for apps still missing a size — e.g. when the screen
    /// reappears after `cancelSizing()` stopped a half-finished pass.
    func resumeSizingIfNeeded() {
        guard phase == .ready else { return }
        let pending = apps.filter { sizes[$0.id] == nil }
        guard !pending.isEmpty else { return }
        sizingTask?.cancel()
        startSizing(pending)
    }

    /// Stop dispatching size walks (at most a handful in flight finish and
    /// their results are discarded). Called when the screen disappears.
    func cancelSizing() { sizingTask?.cancel() }

    private func startSizing(_ apps: [InstalledApp]) {
        let engine = discovery
        sizingTask = Task { [weak self] in
            for await (id, bytes) in engine.sizeStream(for: apps) {
                guard let self, !Task.isCancelled else { break }
                self.sizes[id] = bytes
                self.sizedCount += 1
            }
        }
    }

    func uninstall(_ app: InstalledApp) async {
        guard canUninstall(app), let plan = plans[app.id] else { return }
        let selected = selectedIDs(for: app)
        guard !selected.isEmpty else { return }

        let engine = uninstaller
        let report = await Task.detached(priority: .userInitiated) {
            engine.uninstall(plan, selecting: selected, dryRun: false)
        }.value

        reports[app.id] = report
        if report.trashed.contains(app.url.path) {
            // The bundle itself went to the Trash — treat the app as removed.
            removedAppIDs.insert(app.id)
            expandedAppID = nil
        }
        // Otherwise the bundle wasn't removed (deselected, failed, or blocked):
        // leave the row expanded with its plan so the problem banner is visible.
        // The now-stale plan is rebuilt from disk when the row is re-expanded.
    }
}
