import Foundation
import Observation
import CleanCore

/// Drives the Mail Attachments screen. Everything found is selected by default
/// — these are Mail's local *copies* of attachments (the originals stay with
/// their messages), so removing them is safe and fully recoverable from the
/// Trash.
@MainActor
@Observable
final class MailAttachmentsViewModel {
    enum Phase: Equatable { case idle, scanning, results, cleaning, done }

    private(set) var phase: Phase = .idle
    /// Everything found, largest first (the scanner's order).
    private(set) var attachments: [MailAttachment] = []
    /// Paths currently selected for cleaning. All-on after a scan.
    private(set) var selected: Set<String> = []
    /// True when a Mail Downloads folder exists but could not be read — the
    /// UI hints that Full Disk Access may be required.
    private(set) var accessDenied = false
    private(set) var lastReport: CleanReport?
    /// True when the last scan was stopped early, so totals are partial.
    private(set) var wasCancelled = false

    // Live progress shown while scanning.
    private(set) var scannedBytes: Int64 = 0
    private(set) var foundCount = 0

    private let scanner = MailAttachmentScanner()
    /// The in-flight walk, kept so Stop can cancel it.
    private var engineTask: Task<MailAttachmentScanResult, Never>?

    init() {}

    /// Preloaded results state for design snapshots — zero disk access.
    /// Everything is selected, matching what a real scan produces.
    init(mockItems: [MailAttachment], accessDenied: Bool = false) {
        attachments = mockItems.sorted { $0.sizeBytes > $1.sizeBytes }
        selected = Set(mockItems.map(\.id))
        self.accessDenied = accessDenied
        phase = .results
    }

    // MARK: - Derived totals

    var totalBytes: Int64 { attachments.reduce(0) { $0 + $1.sizeBytes } }

    var selectedBytes: Int64 {
        attachments.reduce(0) { $0 + (selected.contains($1.id) ? $1.sizeBytes : 0) }
    }

    var selectedCount: Int {
        attachments.reduce(0) { $0 + (selected.contains($1.id) ? 1 : 0) }
    }

    // MARK: - Selection

    func isSelected(_ id: String) -> Bool { selected.contains(id) }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    var allSelected: Bool {
        !attachments.isEmpty && attachments.allSatisfy { selected.contains($0.id) }
    }

    /// Tri-state for the master checkbox: some-but-not-all shows the minus.
    var selectAllState: CheckState {
        if selectedCount == 0 { return .off }
        return selectedCount == attachments.count ? .on : .mixed
    }

    func toggleAll() {
        if allSelected { selected = [] }
        else { selected = Set(attachments.map(\.id)) }
    }

    // MARK: - Scan / clean

    func startScan() {
        Task { await scan() }
    }

    func scan() async {
        engineTask?.cancel()
        phase = .scanning
        attachments = []
        selected = []
        accessDenied = false
        lastReport = nil
        wasCancelled = false
        scannedBytes = 0
        foundCount = 0

        let engine = scanner
        let onFound: @Sendable (MailAttachment) -> Void = { attachment in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .scanning else { return }
                self.scannedBytes += attachment.sizeBytes
                self.foundCount += 1
            }
        }

        let task = Task.detached(priority: .userInitiated) {
            engine.scan(shouldContinue: { !Task.isCancelled }, onFound: onFound)
        }
        engineTask = task

        let result = await task.value
        // A newer scan() superseded this one; its completion owns the state.
        guard engineTask == task else { return }
        attachments = result.attachments
        accessDenied = result.accessDenied
        selected = Set(result.attachments.map(\.id))
        wasCancelled = task.isCancelled
        engineTask = nil
        phase = .results
    }

    /// Cancel the in-flight walk; the scan lands on whatever was found so far.
    func stopScan() {
        engineTask?.cancel()
    }

    func clean() async {
        let targets = attachments.filter { selected.contains($0.id) }
        guard !targets.isEmpty else { return }
        phase = .cleaning

        let engine = scanner
        let report = await Task.detached(priority: .userInitiated) {
            engine.remove(targets, dryRun: false)
        }.value

        // Drop what actually moved to the Trash so the on-screen totals stay
        // honest; skipped/failed items stay listed.
        let trashed = Set(report.trashed)
        attachments.removeAll { trashed.contains($0.path) }
        selected.subtract(trashed)
        lastReport = report
        phase = .done
    }
}
