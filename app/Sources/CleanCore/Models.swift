import Foundation

// MARK: - Cleanup rules (declarative)

/// A single location the cleaner is allowed to look at, plus how to treat it.
///
/// Rules are *declarative* on purpose: the set of places we ever touch is a
/// fixed, reviewable list. There is no code path that deletes something not
/// described by one of these targets.
public struct CleanupTarget: Sendable, Equatable {
    /// How the items under `path` are selected.
    public enum Scope: Sendable, Equatable {
        /// Every immediate child of `path` (the directory itself is kept).
        case contents
        /// Only immediate children whose name matches one of these globs.
        case matching([String])
    }

    /// Directory to inspect. May start with `~` (expanded at scan time).
    public let path: String
    public let scope: Scope
    /// If set, only items whose modification date is older than this are eligible.
    public let minAgeDays: Int?

    public init(path: String, scope: Scope = .contents, minAgeDays: Int? = nil) {
        self.path = path
        self.scope = scope
        self.minAgeDays = minAgeDays
    }

    /// The target's base directory with a leading `~` expanded — the same
    /// expansion the scanner itself applies, so callers comparing paths
    /// against scan results agree with what was actually walked.
    public var expandedURL: URL { Scanner.expand(path) }
}

/// A user-facing group of cleanable things (e.g. "User Caches").
public struct CleanupCategory: Identifiable, Sendable, Equatable {
    public let id: String
    public let nameEN: String
    public let nameCN: String
    public let detailEN: String
    public let detailCN: String
    public let targets: [CleanupTarget]
    /// True if any target lives outside the user's home and needs elevated
    /// privileges. MVP categories are all `false` (no root required).
    public let requiresRoot: Bool

    public init(
        id: String,
        nameEN: String,
        nameCN: String,
        detailEN: String = "",
        detailCN: String = "",
        targets: [CleanupTarget],
        requiresRoot: Bool = false
    ) {
        self.id = id
        self.nameEN = nameEN
        self.nameCN = nameCN
        self.detailEN = detailEN
        self.detailCN = detailCN
        self.targets = targets
        self.requiresRoot = requiresRoot
    }
}

// MARK: - Scan results

/// One concrete thing found on disk that can be reclaimed.
public struct ScanItem: Identifiable, Sendable, Hashable {
    public let url: URL
    public let categoryID: String
    public let sizeBytes: Int64
    public let modificationDate: Date?

    public var id: String { url.path }
    public var path: String { url.path }

    public init(url: URL, categoryID: String, sizeBytes: Int64, modificationDate: Date?) {
        self.url = url
        self.categoryID = categoryID
        self.sizeBytes = sizeBytes
        self.modificationDate = modificationDate
    }
}

/// All items found for one category.
public struct ScanResultGroup: Identifiable, Sendable {
    public let category: CleanupCategory
    public let items: [ScanItem]

    public var id: String { category.id }
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }

    public init(category: CleanupCategory, items: [ScanItem]) {
        self.category = category
        self.items = items
    }
}

// MARK: - Formatting

public enum ByteFormat {
    /// Human-readable size, e.g. "1.2 GB", matching Finder's convention.
    public static func human(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
