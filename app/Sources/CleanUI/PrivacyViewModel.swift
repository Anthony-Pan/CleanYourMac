import Foundation
import Observation
import AppKit
import CleanCore

/// Drives the Privacy screen. Browsers are scanned up front; each trace is
/// selected per item. Low-impact traces (cache, history, download list) are
/// pre-selected; disruptive ones (cookies, open tabs) are opt-in and clearly
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

    /// True if the current selection includes cookies (clearing them signs the
    /// user out of websites) — surfaced in the final confirmation.
    var selectedSignsOut: Bool {
        groups.flatMap(\.items).contains { selected.contains($0.id) && $0.signsOut }
    }

    /// True if the current selection includes an open-tabs/session trace.
    var selectedLosesTabs: Bool {
        groups.flatMap(\.items).contains { selected.contains($0.id) && $0.kind == .sessions }
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

    // MARK: - Scan / clean

    func scan() async {
        phase = .scanning
        selected = []
        lastReport = nil
        // Re-read running apps now — the model outlives app launch, so a browser
        // opened since then must still trigger its "quit first" warning.
        runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let engine = scanner

        let found = await Task.detached(priority: .userInitiated) { engine.scan() }.value
        groups = found
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
