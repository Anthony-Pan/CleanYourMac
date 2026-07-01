import Foundation

/// Safety gate for the uninstaller — the same spirit as `SafetyPolicy`
/// (allowlist of roots + protected denylist + symlink resolution) but tuned to
/// uninstall semantics:
///
///  * An uninstallable `.app` lives *directly inside* an app root
///    (`/Applications`, `/Applications/Utilities`, `~/Applications`). That is a
///    depth of 3, so the generic minimum-depth-4 guard is relaxed to 3 for
///    bundles only.
///  * A "leftover" is a *named child* of a fixed set of `~/Library`
///    subdirectories. We only ever remove that named child — never the
///    directory itself, and never anything outside those roots.
///
/// Every path the uninstaller touches — the bundle and each leftover — is
/// validated here, and again inside `AppUninstaller` immediately before
/// disposal (defense in depth). Symlinks are resolved first, so nothing can
/// point its way out of an allowed root.
public struct UninstallPolicy: Sendable {
    /// Directories an uninstallable `.app` may live directly inside.
    public let appRoots: [URL]
    /// `~/Library` subdirectories whose named children may be removed as leftovers.
    public let leftoverRoots: [URL]
    /// Never deleted (or have an ancestor deleted) — system + irreplaceable
    /// personal locations. Reuses `SafetyPolicy`'s denylist.
    public let protectedPaths: [URL]

    public init(
        appRoots: [URL] = UninstallPolicy.defaultAppRoots,
        leftoverRoots: [URL] = UninstallPolicy.defaultLeftoverRoots,
        protectedPaths: [URL] = SafetyPolicy.defaultProtectedPaths
    ) {
        self.appRoots = appRoots.map { $0.canonicalized }
        self.leftoverRoots = leftoverRoots.map { $0.canonicalized }
        self.protectedPaths = protectedPaths.map { $0.canonicalized }
    }

    // MARK: - Validation

    /// Returns `nil` if `url` is safe to remove as an application bundle,
    /// otherwise the reason it is refused. Requires a `.app` extension and that
    /// the (symlink-resolved) path is a strict descendant of an app root.
    public func validateBundle(_ url: URL) -> SafetyRejection? {
        guard url.pathExtension == "app" else {
            return SafetyRejection(reason: .outsideAllowedRoots, path: url.path)
        }
        // Bundles live at depth 3 (e.g. /Applications/Foo.app), so 3 not 4.
        return validate(url, allowedRoots: appRoots, minimumDepth: 3)
    }

    /// Returns `nil` if `url` is safe to remove as a leftover file/dir,
    /// otherwise the reason it is refused.
    public func validateLeftover(_ url: URL) -> SafetyRejection? {
        validate(url, allowedRoots: leftoverRoots, minimumDepth: 4)
    }

    /// Shared gate: shallow → protected → the-root-itself → outside-roots.
    /// Identical in structure to `SafetyPolicy.validate`, with injectable roots
    /// and minimum depth.
    private func validate(_ url: URL, allowedRoots: [URL], minimumDepth: Int) -> SafetyRejection? {
        let target = url.canonicalized

        if target.pathComponents.count < minimumDepth {
            return SafetyRejection(reason: .tooShallow, path: target.path)
        }
        for protectedPath in protectedPaths where target.isSameOrAncestor(of: protectedPath) {
            return SafetyRejection(reason: .protectedPath, path: target.path)
        }
        if allowedRoots.contains(where: { $0.hasSamePath(as: target) }) {
            return SafetyRejection(reason: .isAllowedRootItself, path: target.path)
        }
        guard allowedRoots.contains(where: { $0.isStrictAncestor(of: target) }) else {
            return SafetyRejection(reason: .outsideAllowedRoots, path: target.path)
        }
        return nil
    }

    // MARK: - Defaults

    public static var defaultAppRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            home.appendingPathComponent("Applications"),
        ]
    }

    /// The no-root, user-owned leftover locations (all under `~/Library`).
    /// Deliberately excludes every `/Library/**`, `/private/var/**`, kext,
    /// daemon, privileged-helper and pkg-receipt location — those require root
    /// and are out of scope for a user-safe uninstaller.
    public static var defaultLeftoverRoots: [URL] {
        let lib = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return [
            "Application Support",
            "Caches",
            "Preferences",
            "Preferences/ByHost",
            "SyncedPreferences",
            "Containers",
            "Group Containers",
            "Saved Application State",
            "Logs",
            "HTTPStorages",
            "WebKit",
            "Cookies",
            "LaunchAgents",
            "Application Scripts",
        ].map { lib.appendingPathComponent($0) }
    }
}
