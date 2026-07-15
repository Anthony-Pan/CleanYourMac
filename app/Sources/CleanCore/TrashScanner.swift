import Foundation

// MARK: - Model

/// One top-level thing the user threw away — a file or folder sitting in the
/// Trash. A discarded folder is a single row; its contents were discarded
/// together and are removed together.
public struct TrashItem: Identifiable, Sendable, Hashable {
    public let url: URL
    public let sizeBytes: Int64
    public let modificationDate: Date?
    public let isDirectory: Bool

    public var id: String { url.path }
    public var path: String { url.path }
    public var name: String { url.lastPathComponent }

    public init(url: URL, sizeBytes: Int64, modificationDate: Date?, isDirectory: Bool) {
        self.url = url
        self.sizeBytes = sizeBytes
        self.modificationDate = modificationDate
        self.isDirectory = isDirectory
    }
}

public extension Array where Element == TrashItem {
    /// Sum of every item's size — what emptying all of it would free.
    var totalBytes: Int64 { reduce(0) { $0 + $1.sizeBytes } }
}

// MARK: - Scanner

/// Lists what is sitting in the user's Trash. Read-only — `TrashScanner`
/// never modifies the filesystem.
///
/// Scope: the user's primary Trash only. Per-volume trashes on external
/// disks (`/Volumes/*/.Trashes`) are out of scope for this module.
public struct TrashScanner: Sendable {
    /// Fixed declarative root, resolved once at init. Injectable for tests.
    public let trashRoot: URL

    public init(trashRoot: URL = TrashScanner.defaultTrashRoot()) {
        self.trashRoot = trashRoot
    }

    /// The user's Trash as reported by the system, falling back to `~/.Trash`.
    public static func defaultTrashRoot() -> URL {
        FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }

    /// Top-level items of the Trash, largest first. Directory sizes are
    /// recursive (allocated bytes, mirroring `Scanner`; symlinks are never
    /// followed). Items that fail to stat are skipped rather than crashing.
    /// `onItem` fires synchronously as each item is sized, for live progress.
    public func scan(onItem: ((TrashItem) -> Void)? = nil) -> [TrashItem] {
        let fm = FileManager.default
        let children = (try? fm.contentsOfDirectory(
            at: trashRoot, includingPropertiesForKeys: nil, options: []
        )) ?? []

        var items: [TrashItem] = []
        for child in children {
            // Finder's bookkeeping file, not something the user threw away.
            if child.lastPathComponent == ".DS_Store" { continue }

            // lstat semantics: never traverses a final symlink, so a link is
            // described (and, if allowed, removed) as the link itself.
            guard let attrs = try? fm.attributesOfItem(atPath: child.path),
                  let type = attrs[.type] as? FileAttributeType else { continue }

            let isDirectory = type == .typeDirectory
            let size: Int64
            if type == .typeSymbolicLink {
                size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            } else {
                size = Scanner.allocatedSize(of: child)
            }

            let item = TrashItem(
                url: child,
                sizeBytes: size,
                modificationDate: attrs[.modificationDate] as? Date,
                isDirectory: isDirectory
            )
            items.append(item)
            onItem?(item)
        }
        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}

// MARK: - Report

/// Outcome of one permanent-removal pass — mirrors `CleanReport`, except the
/// items are *removed*, not trashed: there is no undo.
public struct TrashRemovalReport: Sendable {
    public var removed: [String] = []
    public var blocked: [SafetyRejection] = []
    public var failed: [CleanFailure] = []
    public var freedBytes: Int64 = 0

    public init() {}
}

// MARK: - Remover

/// Permanently deletes items out of the Trash. This is the one place in the
/// app where deletion is genuinely permanent — the items were already deleted
/// once when the user threw them away, so there is no Trash to move them to.
///
/// Every URL must pass a `SafetyPolicy` whose single allowed root is the
/// Trash directory (fixed and declarative — never derived from the items
/// being deleted). The policy resolves symlinks, so a link that points
/// outside the Trash is refused rather than followed, and the Trash
/// directory itself is always refused.
public struct TrashRemover: Sendable {
    public let trashRoot: URL
    public let policy: SafetyPolicy

    public init(trashRoot: URL = TrashScanner.defaultTrashRoot()) {
        self.trashRoot = trashRoot
        self.policy = SafetyPolicy(allowedRoots: [trashRoot])
    }

    public func remove(_ items: [TrashItem]) -> TrashRemovalReport {
        var report = TrashRemovalReport()
        let fm = FileManager.default

        for item in items {
            // SAFETY GATE: refuse anything outside the Trash, the Trash root
            // itself, or a symlink that resolves elsewhere.
            if let rejection = policy.validate(item.url) {
                report.blocked.append(rejection)
                continue
            }

            do {
                try fm.removeItem(at: item.url)
                report.removed.append(item.path)
                report.freedBytes += item.sizeBytes
            } catch {
                report.failed.append(CleanFailure(path: item.path, error: String(describing: error)))
            }
        }
        return report
    }
}
