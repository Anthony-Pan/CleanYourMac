import Foundation
import Observation
import CleanCore

/// Drives the Large & Old Files screen. Files are discovered once (at a low base
/// threshold) and then filtered/sorted entirely in memory, so changing the size,
/// age, type, search or grouping is instant and never re-hits the disk.
///
/// Selection starts *empty* on purpose: these are the user's own documents, so
/// nothing is ever pre-selected — every file is an explicit, reviewed choice.
/// Files hidden by any filter (size, age, type, search, ignore list) can never
/// be removed: `clean()` only acts on the selected ∩ visible set.
@MainActor
@Observable
final class LargeFilesViewModel {
    enum Phase: Equatable { case idle, scanning, results, cleaning, done }

    /// Minimum size the *scan* collects. Filtering to larger thresholds happens
    /// in memory, so this is the smallest size the user can ever drill down to.
    /// 50 MB matches the floor CleanMyMac uses for its Large & Old Files scan.
    static let baseThresholdBytes: Int64 = 50 * 1_000_000   // 50 MB

    enum SizeFilter: String, CaseIterable, Identifiable {
        case mb50, mb100, mb500, gb1, gb5
        var id: String { rawValue }
        var bytes: Int64 {
            switch self {
            case .mb50:  return 50 * 1_000_000
            case .mb100: return 100 * 1_000_000
            case .mb500: return 500 * 1_000_000
            case .gb1:   return 1_000 * 1_000_000
            case .gb5:   return 5_000 * 1_000_000
            }
        }
        var label: String {
            switch self {
            case .mb50:  return "50 MB+"
            case .mb100: return "100 MB+"
            case .mb500: return "500 MB+"
            case .gb1:   return "1 GB+"
            case .gb5:   return "5 GB+"
            }
        }
    }

    enum AgeFilter: String, CaseIterable, Identifiable {
        case any, d30, d90, d180, y1, y2
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .any:  return nil
            case .d30:  return 30
            case .d90:  return 90
            case .d180: return 180
            case .y1:   return 365
            case .y2:   return 730
            }
        }
        var label: String {
            switch self {
            case .any:  return "Any age"
            case .d30:  return "30d+"
            case .d90:  return "90d+"
            case .d180: return "180d+"
            case .y1:   return "1y+"
            case .y2:   return "2y+"
            }
        }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case largest, oldest, newest, name, kind
        var id: String { rawValue }
        var label: String {
            switch self {
            case .largest: return "Largest"
            case .oldest:  return "Oldest"
            case .newest:  return "Newest"
            case .name:    return "Name"
            case .kind:    return "Kind"
            }
        }
    }

    enum Grouping: String, CaseIterable, Identifiable {
        case none, kind
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return "Flat list"
            case .kind: return "By kind"
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var allFiles: [LargeFile] = []
    /// Paths explicitly selected for removal. Empty by default (safety).
    private(set) var selected: Set<String> = []
    private(set) var lastReport: CleanReport?

    /// Live scan progress (entries examined / large files found so far).
    private(set) var progressScanned = 0
    private(set) var progressFound = 0

    /// User-added scan roots (validated by `ScanLocationPolicy`), persisted.
    private(set) var customRoots: [URL] = []
    /// Paths the user chose to hide from results — a UI veil, never a deletion
    /// list. Persisted across scans.
    private(set) var ignoredPaths: Set<String> = []
    /// Why the most recent "add folder" was refused (drives an alert).
    var locationError: String?

    var sizeFilter: SizeFilter = .mb100
    var ageFilter: AgeFilter = .any
    var sort: SortOrder = .largest
    var grouping: Grouping = .none
    var searchText: String = ""
    /// Active type buckets; empty means "all types".
    var typeFilter: Set<FileKind> = []

    private static let customRootsKey = "largeFiles.customRoots"
    private static let ignoredPathsKey = "largeFiles.ignoredPaths"

    private let defaults: UserDefaults
    private let now: Date
    /// The in-flight engine walk, kept so Stop can cancel it.
    private var engineTask: Task<[LargeFile], Never>?

    init(now: Date = Date(), defaults: UserDefaults = .standard) {
        self.now = now
        self.defaults = defaults
        loadPersisted()
    }

    /// Preloaded state for design previews (no disk access).
    init(mockFiles: [LargeFile], now: Date = Date()) {
        self.now = now
        self.defaults = .standard
        allFiles = mockFiles
        phase = .results
    }

    // MARK: - Persistence

    private func loadPersisted() {
        // Re-validate stored roots on load — a folder may have been deleted or
        // become unsafe since it was added; silently drop anything invalid.
        let storedRoots = defaults.stringArray(forKey: Self.customRootsKey) ?? []
        customRoots = storedRoots
            .map { URL(fileURLWithPath: $0) }
            .filter { ScanLocationPolicy.validate($0) == nil }

        let storedIgnored = defaults.stringArray(forKey: Self.ignoredPathsKey) ?? []
        ignoredPaths = Set(storedIgnored)
    }

    private func persistRoots() {
        defaults.set(customRoots.map(\.path), forKey: Self.customRootsKey)
    }

    private func persistIgnored() {
        defaults.set(Array(ignoredPaths), forKey: Self.ignoredPathsKey)
    }

    // MARK: - Scan locations

    /// Default content folders plus the user's custom roots, skipping any custom
    /// root already covered by (equal to or inside) a default one.
    var effectiveRoots: [URL] {
        let defaultRoots = FileFinder.defaultRoots
        let extras = customRoots.filter { custom in
            !defaultRoots.contains { $0.isSameOrAncestor(of: custom) }
        }
        return defaultRoots + extras
    }

    func addCustomRoot(_ url: URL) {
        if let reason = ScanLocationPolicy.validate(url) {
            locationError = reason
            return
        }
        let canonical = url.canonicalized
        if effectiveRoots.contains(where: { $0.isSameOrAncestor(of: canonical) }) {
            locationError = "That folder is already covered by an existing scan location."
            return
        }
        customRoots.append(canonical)
        persistRoots()
        Task { await scan() }
    }

    func removeCustomRoot(_ url: URL) {
        customRoots.removeAll { $0.hasSamePath(as: url) }
        persistRoots()
        Task { await scan() }
    }

    // MARK: - Derived

    /// Files passing the current size / age / type / search / ignore filters,
    /// in the chosen order. The single source of truth for what can be acted on.
    var visibleFiles: [LargeFile] {
        let minBytes = sizeFilter.bytes
        let minDays = ageFilter.days
        let types = typeFilter
        let query = searchText.trimmingCharacters(in: .whitespaces)

        let filtered = allFiles.filter { file in
            guard file.sizeBytes >= minBytes else { return false }
            if let minDays, !file.isOlder(thanDays: minDays, now: now) { return false }
            if !types.isEmpty, !types.contains(file.kind) { return false }
            if ignoredPaths.contains(file.path) { return false }
            if !query.isEmpty, !file.name.localizedCaseInsensitiveContains(query) { return false }
            return true
        }

        switch sort {
        case .largest:
            return filtered.sorted { $0.sizeBytes > $1.sizeBytes }
        case .oldest:
            return filtered.sorted {
                ($0.lastUsedDate ?? .distantFuture) < ($1.lastUsedDate ?? .distantFuture)
            }
        case .newest:
            return filtered.sorted {
                ($0.lastUsedDate ?? .distantPast) > ($1.lastUsedDate ?? .distantPast)
            }
        case .name:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .kind:
            return filtered.sorted {
                if $0.kind != $1.kind { return $0.kind.titleEN < $1.kind.titleEN }
                return $0.sizeBytes > $1.sizeBytes
            }
        }
    }

    /// Presentation of `visibleFiles` as per-kind sections (largest total
    /// first) for the grouped view. Purely a re-arrangement — selection and
    /// clean() keep operating on `visibleFiles`.
    var sections: [(kind: FileKind, files: [LargeFile])] {
        var byKind: [FileKind: [LargeFile]] = [:]
        for file in visibleFiles { byKind[file.kind, default: []].append(file) }
        return byKind
            .map { (kind: $0.key, files: $0.value) }
            .sorted { a, b in
                a.files.reduce(0) { $0 + $1.sizeBytes } > b.files.reduce(0) { $0 + $1.sizeBytes }
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

    var ignoredCount: Int { ignoredPaths.count }

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

    // MARK: - Ignore list

    /// Hide a file from results (this scan and future ones). Purely cosmetic —
    /// the file is never touched; it is also dropped from the selection so an
    /// ignored file can never remain silently selected.
    func ignore(_ file: LargeFile) {
        ignoredPaths.insert(file.path)
        selected.remove(file.id)
        persistIgnored()
    }

    func clearIgnoreList() {
        ignoredPaths = []
        persistIgnored()
    }

    // MARK: - Scan / clean

    func scan() async {
        engineTask?.cancel()
        phase = .scanning
        selected = []
        lastReport = nil
        progressScanned = 0
        progressFound = 0

        let engine = FileFinder(roots: effectiveRoots)
        let threshold = Self.baseThresholdBytes
        let asOf = now
        let onProgress: @Sendable (Int, Int) -> Void = { scanned, foundCount in
            Task { @MainActor [weak self] in
                self?.progressScanned = scanned
                self?.progressFound = foundCount
            }
        }

        let task = Task.detached(priority: .userInitiated) {
            engine.find(
                minSizeBytes: threshold,
                now: asOf,
                shouldContinue: { !Task.isCancelled },
                onProgress: onProgress
            )
        }
        engineTask = task

        // A cancelled walk still returns everything found so far, so Stop lands
        // on partial results instead of an empty screen.
        allFiles = await task.value
        engineTask = nil
        phase = .results
    }

    /// Cancel the in-flight walk; the scan finishes early with partial results.
    func stopScan() {
        engineTask?.cancel()
    }

    func clean() async {
        // Remove only files that are both selected AND currently visible.
        let targets = visibleFiles.filter { selected.contains($0.id) }
        guard !targets.isEmpty else { return }
        phase = .cleaning
        let engine = FileFinder(roots: effectiveRoots)

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
