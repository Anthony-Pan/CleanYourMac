import Foundation
import Observation
import CleanCore

/// Drives the Smart Scan dashboard: one Scan button runs every module's scan
/// concurrently (System Junk, Large & Old Files, Privacy, Applications) and
/// the results screen summarizes what each area found.
///
/// This model owns no engine and no results — it orchestrates the four module
/// view models that `RootView` already keeps alive, so opening a module after
/// a Smart Scan lands on its fully loaded screen. Cleaning always happens
/// inside the module screens; every confirmation dialog and safety warning
/// stays exactly where it was designed.
@MainActor
@Observable
final class SmartScanViewModel {
    enum Phase: Equatable { case idle, scanning, results }

    /// The four areas covered by one Smart Scan, in display order.
    enum Module: String, CaseIterable, Identifiable {
        case junk, largeFiles, privacy, apps
        var id: String { rawValue }
    }

    enum ModuleState: Equatable { case waiting, running, done }

    private(set) var phase: Phase = .idle
    private(set) var states: [Module: ModuleState]
    /// True when the user pressed Stop — junk and large-file totals may be
    /// partial (their engines land on whatever was found so far).
    private(set) var wasCancelled = false

    let junk: ScanViewModel
    let files: LargeFilesViewModel
    let privacy: PrivacyViewModel
    let apps: UninstallViewModel

    private var scanTask: Task<Void, Never>?

    init(junk: ScanViewModel,
         files: LargeFilesViewModel,
         privacy: PrivacyViewModel,
         apps: UninstallViewModel) {
        self.junk = junk
        self.files = files
        self.privacy = privacy
        self.apps = apps
        states = Self.states(.waiting)
    }

    /// Preloaded state for design previews (no disk access): every module is
    /// done and the dashboard shows their mock results.
    init(mockJunk: ScanViewModel,
         mockFiles: LargeFilesViewModel,
         mockPrivacy: PrivacyViewModel,
         mockApps: UninstallViewModel) {
        junk = mockJunk
        files = mockFiles
        privacy = mockPrivacy
        apps = mockApps
        states = Self.states(.done)
        phase = .results
    }

    private static func states(_ state: ModuleState) -> [Module: ModuleState] {
        Dictionary(uniqueKeysWithValues: Module.allCases.map { ($0, state) })
    }

    func state(_ module: Module) -> ModuleState { states[module] ?? .waiting }

    // MARK: - Derived totals (read straight from the module models, so the
    // dashboard always matches what each module screen shows)

    var doneCount: Int { Module.allCases.filter { state($0) == .done }.count }
    var moduleCount: Int { Module.allCases.count }

    /// Junk bytes: live counter while its scan streams, settled group totals
    /// afterwards (the two agree once the scan lands).
    var junkBytes: Int64 {
        junk.phase == .scanning
            ? junk.scannedBytes
            : junk.groups.reduce(0) { $0 + $1.totalBytes }
    }

    var junkItemCount: Int {
        junk.phase == .scanning
            ? junk.foundCount
            : junk.groups.reduce(0) { $0 + $1.items.count }
    }

    /// Large files: the same filtered set the module screen shows (its default
    /// size floor), so the card number matches the screen it opens.
    var filesBytes: Int64 { files.visibleBytes }
    var filesCount: Int { files.visibleFiles.count }

    var privacyBytes: Int64 { privacy.totalBytes }
    /// Rendered trace rows, matching the Privacy screen's row count.
    var privacyTraceCount: Int {
        privacy.groups.reduce(0) { $0 + privacy.aggregatedRows(for: $1).count }
    }
    var privacyFindingCount: Int { privacy.findings.count }

    var appCount: Int {
        apps.apps.filter { !apps.removedAppIDs.contains($0.id) }.count
    }

    /// Total on-disk size of installed apps, or nil while bundle sizes are
    /// still streaming in (render a shimmer, never a partial sum).
    var appsSizedBytes: Int64? {
        guard apps.phase == .ready, !apps.isSizing else { return nil }
        return apps.apps.reduce(0) { $0 + (apps.sizes[$1.id] ?? 0) }
    }

    /// Everything found that can be reviewed and reclaimed: junk + privacy
    /// traces + large files. App bundle sizes are intentionally excluded —
    /// installed apps are not junk.
    var foundBytes: Int64 { junkBytes + filesBytes + privacyBytes }

    // MARK: - Scan

    /// Run every module's scan concurrently. Each module flips to `.done` as
    /// its own scan lands; the dashboard reaches `.results` when all four have.
    func startScan() {
        scanTask?.cancel()
        wasCancelled = false
        phase = .scanning
        states = Self.states(.running)

        let junkRun = junk.startScan()
        let filesModel = files
        let privacyModel = privacy
        let appsModel = apps

        scanTask = Task {
            await withTaskGroup(of: Module.self) { group in
                group.addTask { @MainActor in
                    await junkRun.value
                    return .junk
                }
                group.addTask { @MainActor in
                    await filesModel.scan()
                    return .largeFiles
                }
                group.addTask { @MainActor in
                    await privacyModel.scan()
                    return .privacy
                }
                group.addTask { @MainActor in
                    await appsModel.scan()
                    return .apps
                }
                for await module in group {
                    states[module] = .done
                }
            }
            phase = .results
        }
    }

    /// Stop the cancellable engines (junk walk, large-file walk); both land on
    /// partial results. Privacy and app discovery have no mid-flight cancel —
    /// they are quick and finish on their own, so their numbers stay complete.
    func stopScan() {
        guard phase == .scanning else { return }
        wasCancelled = true
        junk.cancelScan()
        files.stopScan()
    }
}
