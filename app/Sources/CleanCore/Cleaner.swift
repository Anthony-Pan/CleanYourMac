import Foundation

// MARK: - Disposer abstraction (so deletion is reversible AND testable)

/// How an item is disposed of. The production implementation moves items to the
/// Trash so the user can always undo. Tests inject a recording disposer.
public protocol FileDisposer: Sendable {
    func dispose(_ url: URL) throws
}

/// Moves the item to the user's Trash. Never permanently deletes — the whole
/// point is that a cleanup can be undone from Finder.
public struct TrashDisposer: FileDisposer {
    public init() {}

    public func dispose(_ url: URL) throws {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
    }
}

// MARK: - Report

public struct CleanFailure: Sendable, Equatable {
    public let path: String
    public let error: String
}

public struct CleanReport: Sendable {
    public var trashed: [String] = []
    public var blocked: [SafetyRejection] = []
    public var failed: [CleanFailure] = []
    public var freedBytes: Int64 = 0
    public let dryRun: Bool

    public init(dryRun: Bool) { self.dryRun = dryRun }
}

// MARK: - Cleaner

/// Executes a cleanup. Re-validates every item against the `SafetyPolicy`
/// immediately before disposing of it (defense in depth — even if a stale or
/// hand-crafted `ScanItem` slips through, the gate runs again here).
public struct Cleaner {
    public let policy: SafetyPolicy
    public let disposer: FileDisposer

    public init(policy: SafetyPolicy, disposer: FileDisposer = TrashDisposer()) {
        self.policy = policy
        self.disposer = disposer
    }

    /// - Parameter dryRun: when true, nothing is touched; the report shows what
    ///   *would* be trashed and how much space it *would* free.
    public func clean(_ items: [ScanItem], dryRun: Bool) -> CleanReport {
        var report = CleanReport(dryRun: dryRun)

        for item in items {
            // SAFETY GATE (again): refuse anything the policy rejects.
            if let rejection = policy.validate(item.url) {
                report.blocked.append(rejection)
                continue
            }

            if dryRun {
                report.trashed.append(item.path)
                report.freedBytes += item.sizeBytes
                continue
            }

            do {
                try disposer.dispose(item.url)
                report.trashed.append(item.path)
                report.freedBytes += item.sizeBytes
            } catch {
                report.failed.append(CleanFailure(path: item.path, error: String(describing: error)))
            }
        }

        return report
    }
}
