import Foundation

// MARK: - URL path helpers (canonical, symlink-resolved comparisons)

public extension URL {
    /// Fully resolved, standardized form. Resolves symlinks so an item cannot
    /// "escape" an allowed root by being a symlink pointing elsewhere.
    var canonicalized: URL {
        resolvingSymlinksInPath().standardizedFileURL
    }

    /// Path-component equality (robust to trailing slashes).
    func hasSamePath(as other: URL) -> Bool {
        pathComponents == other.pathComponents
    }

    /// True if `self` is a strict ancestor directory of `other`.
    func isStrictAncestor(of other: URL) -> Bool {
        let a = pathComponents
        let b = other.pathComponents
        guard a.count < b.count else { return false }
        return Array(b.prefix(a.count)) == a
    }

    func isSameOrAncestor(of other: URL) -> Bool {
        hasSamePath(as: other) || isStrictAncestor(of: other)
    }
}

// MARK: - Rejections

/// Why a path was refused. If `validate` returns nil, the path is safe to act on.
public struct SafetyRejection: Error, Equatable, Sendable {
    public enum Reason: String, Sendable {
        case tooShallow            // e.g. "/", "/Users", "/Users/me"
        case protectedPath         // is, or is an ancestor of, a protected location
        case isAllowedRootItself   // we clean *contents*, never the root directory
        case outsideAllowedRoots   // not inside any declared cleanable location
        /// Matches a never-remove user-content name (passwords/autofill/bookmarks).
        case protectedContent
    }
    public let reason: Reason
    public let path: String
}

// MARK: - SafetyPolicy

/// The gatekeeper. Every path is validated against this before it is scanned
/// or trashed. It is intentionally strict: an allowlist of cleanable roots plus
/// a denylist of protected locations, with symlink resolution so nothing can
/// point its way out.
public struct SafetyPolicy: Sendable {
    /// Canonical directories whose *contents* may be cleaned.
    public let allowedRoots: [URL]
    /// Canonical URLs that may be removed *themselves* — exact matches only,
    /// nothing beside or beneath them is implied. Even stricter than a root;
    /// used for fixed single-location traces (the quarantine database, shell
    /// history files, the QuickLook cache directory).
    public let allowedExactTargets: [URL]
    /// Canonical directories that must never be deleted (or have an ancestor deleted).
    public let protectedPaths: [URL]
    /// Minimum number of path components required. Guards against shallow, catastrophic
    /// targets like "/" or "/Users/me". 4 => at least "/Users/<name>/<something>".
    public let minimumDepth: Int

    public init(
        allowedRoots: [URL],
        allowedExactTargets: [URL] = [],
        protectedPaths: [URL] = SafetyPolicy.defaultProtectedPaths,
        minimumDepth: Int = 4
    ) {
        self.allowedRoots = allowedRoots.map { $0.canonicalized }
        self.allowedExactTargets = allowedExactTargets.map { $0.canonicalized }
        self.protectedPaths = protectedPaths.map { $0.canonicalized }
        self.minimumDepth = minimumDepth
    }

    /// Returns `nil` if `url` is safe to delete, otherwise the reason it is refused.
    public func validate(_ url: URL) -> SafetyRejection? {
        let target = url.canonicalized

        // 1. Never anything shallow enough to be catastrophic.
        if target.pathComponents.count < minimumDepth {
            return SafetyRejection(reason: .tooShallow, path: target.path)
        }

        // 2. Never a protected path or an ancestor of one.
        for protectedPath in protectedPaths where target.isSameOrAncestor(of: protectedPath) {
            return SafetyRejection(reason: .protectedPath, path: target.path)
        }

        // 3. Never an allowed root itself — only its contents.
        if allowedRoots.contains(where: { $0.hasSamePath(as: target) }) {
            return SafetyRejection(reason: .isAllowedRootItself, path: target.path)
        }

        // 4. An explicitly sanctioned exact target passes (its children do not —
        //    a match here is by full-path equality only). Depth and protected-
        //    path checks above still apply.
        if allowedExactTargets.contains(where: { $0.hasSamePath(as: target) }) {
            return nil
        }

        // 5. Must live strictly inside a declared cleanable root.
        guard allowedRoots.contains(where: { $0.isStrictAncestor(of: target) }) else {
            return SafetyRejection(reason: .outsideAllowedRoots, path: target.path)
        }

        return nil
    }

    /// Sensible default denylist: filesystem/system roots and the user's
    /// irreplaceable home locations. These are never touched even if a rule
    /// mistakenly points at them.
    public static var defaultProtectedPaths: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths = [
            "/", "/System", "/Library", "/usr", "/bin", "/sbin",
            "/etc", "/var", "/private", "/Applications", "/Users", "/opt", "/cores",
        ].map { URL(fileURLWithPath: $0) }

        paths.append(home)
        for sub in [
            "Documents", "Desktop", "Downloads", "Movies", "Music", "Pictures",
            "Library", "Library/Mail", "Library/Messages", "Library/Keychains",
            "Library/Application Support", "Library/Photos", "Library/Mobile Documents",
        ] {
            paths.append(home.appendingPathComponent(sub))
        }
        return paths
    }
}
