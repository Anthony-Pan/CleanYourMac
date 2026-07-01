import Foundation
import Observation
import CleanCore

/// Drives the Large & Old Files screen. Files are discovered once (at a low base
/// threshold) and then filtered/sorted entirely in memory, so changing the size,
/// age or type filter is instant and never re-hits the disk.
///
/// Selection starts *empty* on purpose: these are the user's own documents, so
/// nothing is ever pre-selected — every file is an explicit, reviewed choice.
@MainActor
@Observable
final class LargeFilesViewModel {
    enum Phase: Equatable { case idle, scanning, results, cleaning, done }

    /// Minimum size the *scan* collects. Filtering to larger thresholds happens
    /// in memory, so this is the smallest size the user can ever drill down to.
    static let baseThresholdBytes: Int64 = 100 * 1_000_000   // 100 MB

    enum SizeFilter: String, CaseIterable, Identifiable {
        case mb100, mb500, gb1, gb5
        var id: String { rawValue }
        var bytes: Int64 {
            switch self {
            case .mb100: return 100 * 1_000_000
            case .mb500: return 500 * 1_000_000
            case .gb1:   return 1_000 * 1_000_000
            case .gb5:   return 5_000 * 1_000_000
            }
        }
        var label: String {
            switch self {
            case .mb100: return "100 MB+"
            case .mb500: return "500 MB+"
            case .gb1:   return "1 GB+"
            case .gb5:   return "5 GB+"
            }
        }
    }

    enum AgeFilter: String, CaseIterable, Identifiable {
        case any, d30, d90, d180, y1
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .any:  return nil
            case .d30:  return 30
            case .d90:  return 90
            case .d180: return 180
            case .y1:   return 365
            }
        }
        var label: String {
            switch self {
            case .any:  return "Any age"
            case .d30:  return "30d+"
            case .d90:  return "90d+"
            case .d180: return "180d+"
            case .y1:   return "1y+"
            }
        }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case largest, oldest, name
        var id: String { rawValue }
        var label: String {
            switch self {
            case .largest: return "Largest"
            case .oldest:  return "Oldest"
            case .name:    return "Name"
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var allFiles: [LargeFile] = []
    /// Paths explicitly selected for removal. Empty by default (safety).
    private(set) var selected: Set<String> = []
    private(set) var lastReport: CleanReport?

    var sizeFilter: SizeFilter = .mb100
    var ageFilter: AgeFilter = .any
    var sort: SortOrder = .largest
    /// Active type buckets; empty means "all types".
    var typeFilter: Set<FileKind> = []

    private let finder = FileFinder()
    private let now: Date

    init(now: Date = Date()) { self.now = now }

    /// Preloaded state for design previews (no disk access).
    init(mockFiles: [LargeFile], now: Date = Date()) {
        self.now = now
        allFiles = mockFiles
        phase = .results
    }

    // MARK: - Derived

    /// Files passing the current size / age / type filters, in the chosen order.
    var visibleFiles: [LargeFile] {
        let minBytes = sizeFilter.bytes
        let minDays = ageFilter.days
        let types = typeFilter

        let filtered = allFiles.filter { file in
            guard file.sizeBytes >= minBytes else { return false }
            if let minDays, !file.isOlder(thanDays: minDays, now: now) { return false }
            if !types.isEmpty, !types.contains(file.kind) { return false }
            return true
        }

        switch sort {
        case .largest:
            return filtered.sorted { $0.sizeBytes > $1.sizeBytes }
        case .oldest:
            return filtered.sorted { ($0.modificationDate ?? .distantFuture) < ($1.modificationDate ?? .distantFuture) }
        case .name:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    /// Type buckets present in the full result set, largest total first — used
    /// to build the type-filter chips (only offer types we actually found).
    var availableKinds: [FileKind] {
        var totals: [FileKind: Int64] = [:]
        for file in allFiles { totals[file.kind, default: 0] += file.sizeBytes }
        return totals.sorted { $0.value > $1.value }.map(\.key)
    }

    var visibleBytes: Int64 { visibleFiles.reduce(0) { $0 + $1.sizeBytes } }

    /// Only counts selections that are currently visible, so a hidden-by-filter
    /// file can never be swept up by the Clean button.
    var selectedBytes: Int64 {
        visibleFiles.reduce(0) { $0 + (selected.contains($1.id) ? $1.sizeBytes : 0) }
    }

    var selectedCount: Int {
        visibleFiles.reduce(0) { $0 + (selected.contains($1.id) ? 1 : 0) }
    }

    // MARK: - Selection

    func isSelected(_ id: String) -> Bool { selected.contains(id) }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    /// Select / deselect every *currently visible* file (never touches files
    /// hidden by the active filters).
    func toggleAllVisible() {
        let ids = visibleFiles.map(\.id)
        let allOn = !ids.isEmpty && ids.allSatisfy { selected.contains($0) }
        if allOn { ids.forEach { selected.remove($0) } }
        else { ids.forEach { selected.insert($0) } }
    }

    var allVisibleSelected: Bool {
        let ids = visibleFiles.map(\.id)
        return !ids.isEmpty && ids.allSatisfy { selected.contains($0) }
    }

    // MARK: - Scan / clean

    func scan() async {
        phase = .scanning
        selected = []
        lastReport = nil
        let engine = finder
        let threshold = Self.baseThresholdBytes
        let asOf = now

        let files = await Task.detached(priority: .userInitiated) {
            engine.find(minSizeBytes: threshold, now: asOf)
        }.value

        allFiles = files
        phase = .results
    }

    func clean() async {
        // Remove only files that are both selected AND currently visible.
        let targets = visibleFiles.filter { selected.contains($0.id) }
        guard !targets.isEmpty else { return }
        phase = .cleaning
        let engine = finder

        let report = await Task.detached(priority: .userInitiated) {
            engine.remove(targets, dryRun: false)
        }.value

        // Drop the removed files from the in-memory list and clear their
        // selection so the results view reflects reality without a re-scan.
        let trashed = Set(report.trashed)
        allFiles.removeAll { trashed.contains($0.path) }
        selected.subtract(trashed)
        lastReport = report
        phase = .done
    }
}
