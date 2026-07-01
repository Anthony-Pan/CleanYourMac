import Foundation
import Observation
import AppKit
import CleanCore

/// Drives the Uninstaller screen. Apps are discovered up front; a per-app
/// removal plan (bundle + attributed leftovers) is built lazily the first time
/// a row is expanded. Selection is tracked per leftover so the user reviews and
/// excludes individual files before anything is moved to the Trash.
@MainActor
@Observable
final class UninstallViewModel {
    enum Phase: Equatable { case idle, scanning, ready }

    private(set) var phase: Phase = .idle
    private(set) var apps: [InstalledApp] = []
    var query: String = ""

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

    // MARK: - Derived

    /// Apps matching the search box, with already-removed ones dropped.
    var visibleApps: [InstalledApp] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return apps.filter { app in
            guard !removedAppIDs.contains(app.id) else { return false }
            guard !q.isEmpty else { return true }
            return app.name.lowercased().contains(q) || (app.bundleID?.lowercased().contains(q) ?? false)
        }
    }

    var totalBundleBytes: Int64 { visibleApps.reduce(0) { $0 + $1.sizeBytes } }

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

    func scan() async {
        phase = .scanning
        let engine = discovery
        apps = await Task.detached(priority: .userInitiated) { engine.installedApps() }.value
        phase = .ready
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
