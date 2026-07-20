import Foundation
import AppKit
import Observation
import CleanCore

/// Drives the Mail Attachments screen. Everything found is selected by default
/// — these are Mail's local *copies* of attachments (the originals stay with
/// their messages), so removing them is safe and fully recoverable from the
/// Trash.
///
/// Search, size filter and sort are in-memory projections of the scanned
/// results; changing them never re-hits the disk. Rows hidden by any filter
/// can never be removed: `clean()` only acts on the selected ∩ visible set,
/// and every on-screen count is scoped the same way.
@MainActor
@Observable
final class MailAttachmentsViewModel {
    enum Phase: Equatable { case idle, scanning, results, cleaning, done }

    enum SizeFilter: String, CaseIterable, Identifiable {
        case all, mb10, mb100
        var id: String { rawValue }
        /// Inclusive lower bound, in the decimal MB the UI displays.
        var minBytes: Int64 {
            switch self {
            case .all:   return 0
            case .mb10:  return 10 * 1_000_000
            case .mb100: return 100 * 1_000_000
            }
        }
        var label: String {
            switch self {
            case .all:   return "All"
            case .mb10:  return "≥ 10 MB"
            case .mb100: return "≥ 100 MB"
            }
        }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case size, date
        var id: String { rawValue }
        var label: String {
            switch self {
            case .size: return "Largest first"
            case .date: return "Newest first"
            }
        }
        var coreOrder: MailAttachmentSortOrder {
            switch self {
            case .size: return .sizeLargestFirst
            case .date: return .dateNewestFirst
            }
        }
    }

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

    // Filter state — bindable from the view; purely in-memory.
    var searchText = ""
    var sizeFilter: SizeFilter = .all
    var sort: SortOrder = .size

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

    // MARK: - Derived (visible rows are the single source of truth)

    /// Attachments passing the current search/size filters in the chosen
    /// order — exactly what is on screen AND the only rows `clean()` may act
    /// on. A row this projection hides can never be removed.
    var visibleAttachments: [MailAttachment] {
        MailAttachmentFilter.visible(in: attachments,
                                     matchingName: searchText,
                                     minSizeBytes: sizeFilter.minBytes,
                                     sortedBy: sort.coreOrder)
    }

    var isFiltering: Bool {
        sizeFilter != .all
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func clearFilters() {
        searchText = ""
        sizeFilter = .all
    }

    var totalBytes: Int64 { attachments.reduce(0) { $0 + $1.sizeBytes } }

    var visibleBytes: Int64 { visibleAttachments.reduce(0) { $0 + $1.sizeBytes } }

    /// Only counts selections that are currently visible, so every on-screen
    /// total matches what the Clean button will actually do.
    var selectedBytes: Int64 {
        visibleAttachments.reduce(0) { $0 + (selected.contains($1.id) ? $1.sizeBytes : 0) }
    }

    var selectedCount: Int {
        visibleAttachments.reduce(0) { $0 + (selected.contains($1.id) ? 1 : 0) }
    }

    /// Selected rows the filters currently hide. Surfaced in the footer so a
    /// hidden selection is never silently ignored — and never cleaned.
    var hiddenSelectedCount: Int {
        selected.subtracting(visibleAttachments.map(\.id)).count
    }

    // MARK: - Selection

    func isSelected(_ id: String) -> Bool { selected.contains(id) }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    var allVisibleSelected: Bool {
        let ids = visibleAttachments.map(\.id)
        return !ids.isEmpty && ids.allSatisfy { selected.contains($0) }
    }

    /// Tri-state for the master checkbox: some-but-not-all shows the minus.
    var selectAllState: CheckState {
        if selectedCount == 0 { return .off }
        return selectedCount == visibleAttachments.count ? .on : .mixed
    }

    /// Select / deselect every *currently visible* row — never touches rows
    /// hidden by the active filters.
    func toggleAllVisible() {
        let ids = visibleAttachments.map(\.id)
        if allVisibleSelected { ids.forEach { selected.remove($0) } }
        else { ids.forEach { selected.insert($0) } }
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
        // Only rows that are both selected AND currently visible — a row
        // hidden by the search or size filter is never swept up invisibly.
        let targets = visibleAttachments.filter { selected.contains($0.id) }
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

    // MARK: - Shortcuts (never modify anything)

    func reveal(_ attachment: MailAttachment) {
        NSWorkspace.shared.activateFileViewerSelecting([attachment.url])
    }
}
