import Foundation

/// Finds an app's leftover files and moves the app plus its leftovers to the
/// Trash. Building a plan is read-only; nothing is touched until `uninstall` is
/// called with `dryRun: false`, and even then every path is re-validated
/// against `UninstallPolicy` immediately before disposal.
///
/// Matching follows a strict rule: bundle-ID matches (reverse-DNS, collision
/// free) are `high` confidence; heuristic app-name and shared Group-Container
/// matches are `medium` and meant to be reviewed before removal.
public struct AppUninstaller {
    public let policy: UninstallPolicy
    public let disposer: FileDisposer
    /// The `~/Library` base the leftover search walks. Injectable so tests can
    /// point it (and a matching policy) at a sandbox instead of the real home.
    public let libraryURL: URL

    public init(
        policy: UninstallPolicy = UninstallPolicy(),
        disposer: FileDisposer = TrashDisposer(),
        libraryURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
    ) {
        self.policy = policy
        self.disposer = disposer
        self.libraryURL = libraryURL
    }

    // MARK: - Planning (read-only)

    /// Build the full removal plan for `app`: the bundle (when removable) plus
    /// every leftover we can attribute to it. Never touches the filesystem.
    /// System apps always yield an empty plan.
    ///
    /// - Parameter otherAppIDs: bundle identifiers of the *other* apps installed
    ///   on this Mac. A leftover whose id belongs to one of these is never
    ///   attributed to `app` — this is what stops uninstalling `com.google.Chrome`
    ///   from sweeping up a separately-installed `com.google.Chrome.canary`.
    public func plan(for app: InstalledApp, otherAppIDs: Set<String> = []) -> UninstallPlan {
        guard !app.isSystem else { return UninstallPlan(app: app, leftovers: []) }

        var leftovers: [AppLeftover] = []
        if policy.validateBundle(app.url) == nil {
            leftovers.append(AppLeftover(
                url: app.url, kind: .bundle, confidence: .high, sizeBytes: app.sizeBytes))
        }
        let embedded = AppDiscovery.embeddedBundleIDs(of: app.url)
        leftovers.append(contentsOf: findLeftovers(for: app, embeddedIDs: embedded, otherAppIDs: otherAppIDs))

        // De-dup by canonical path (a location can match via two roots).
        var seen = Set<String>()
        let unique = leftovers.filter { seen.insert($0.url.canonicalized.path).inserted }
        return UninstallPlan(app: app, leftovers: unique)
    }

    // MARK: - Execution

    /// Move the selected items to the Trash (or, in `dryRun`, just report what
    /// would happen). `selecting` limits removal to those leftover ids; `nil`
    /// means everything in the plan.
    public func uninstall(
        _ plan: UninstallPlan,
        selecting selected: Set<String>? = nil,
        dryRun: Bool
    ) -> CleanReport {
        var report = CleanReport(dryRun: dryRun)

        for leftover in plan.leftovers {
            if let selected, !selected.contains(leftover.id) { continue }

            // A system app's bundle is never removable, even via a crafted plan.
            if leftover.kind == .bundle, plan.app.isSystem {
                report.blocked.append(SafetyRejection(reason: .protectedPath, path: leftover.url.path))
                continue
            }

            // SAFETY GATE (again): re-validate immediately before disposal.
            let rejection = leftover.kind == .bundle
                ? policy.validateBundle(leftover.url)
                : policy.validateLeftover(leftover.url)
            if let rejection {
                report.blocked.append(rejection)
                continue
            }

            if dryRun {
                report.trashed.append(leftover.url.path)
                report.freedBytes += leftover.sizeBytes
                continue
            }

            do {
                try disposer.dispose(leftover.url)
                report.trashed.append(leftover.url.path)
                report.freedBytes += leftover.sizeBytes
            } catch {
                report.failed.append(CleanFailure(path: leftover.url.path, error: String(describing: error)))
            }
        }

        return report
    }

    // MARK: - Leftover discovery

    private struct Search {
        let root: URL
        let kind: AppLeftover.Kind
        let match: (String) -> AppLeftover.Confidence?
    }

    func findLeftovers(for app: InstalledApp, embeddedIDs: Set<String> = [], otherAppIDs: Set<String> = []) -> [AppLeftover] {
        let fm = FileManager.default
        var out: [AppLeftover] = []

        for search in searches(for: app, embeddedIDs: embeddedIDs, otherAppIDs: otherAppIDs) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: search.root.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let children = (try? fm.contentsOfDirectory(
                at: search.root, includingPropertiesForKeys: nil, options: [])) ?? []

            for child in children {
                guard let confidence = search.match(child.lastPathComponent) else { continue }
                // SAFETY GATE: must resolve to a valid leftover location.
                guard policy.validateLeftover(child) == nil else { continue }
                out.append(AppLeftover(
                    url: child,
                    kind: search.kind,
                    confidence: confidence,
                    sizeBytes: Scanner.allocatedSize(of: child)
                ))
            }
        }
        return out
    }

    /// The per-location search table. Each entry pairs a `~/Library`
    /// subdirectory with the matcher appropriate for how apps name files there.
    private func searches(for app: InstalledApp, embeddedIDs: Set<String>, otherAppIDs: Set<String>) -> [Search] {
        let lib = libraryURL
        func root(_ component: String) -> URL { lib.appendingPathComponent(component) }

        let id = app.bundleID?.lowercased()
        let nameToken = Self.nameToken(for: app.name)
        let embedded = Set(embeddedIDs.map { $0.lowercased() })
        let others = Set(otherAppIDs.map { $0.lowercased() }).subtracting(id.map { [$0] } ?? [])

        // Classify a bundle-id-shaped candidate relative to the target app:
        //  * nil     — not ours (belongs to another installed app, or no match)
        //  * .high   — the app's own id, or a genuinely embedded extension/helper
        //  * .medium — a dotted-namespace neighbour we can't confirm is ours;
        //              shown for review, never auto-selected.
        // This is what prevents `com.google.Chrome` from auto-trashing a
        // separately-installed `com.google.Chrome.canary`.
        func classify(_ candidate: String) -> AppLeftover.Confidence? {
            guard let id else { return nil }
            let lc = candidate.lowercased()
            if others.contains(where: { lc == $0 || lc.hasPrefix($0 + ".") }) { return nil }
            if lc == id { return .high }
            guard lc.hasPrefix(id + ".") else { return nil }
            return embedded.contains(lc) ? .high : .medium
        }
        // Strip a trailing ".suffix" (case-insensitive) if present.
        func strip(_ name: String, _ suffix: String) -> String {
            name.lowercased().hasSuffix("." + suffix) ? String(name.dropLast(suffix.count + 1)) : name
        }
        // Exact `<id>.<suffix>` filename → this app only (siblings can't collide).
        func idFile(_ suffix: String, _ c: String) -> AppLeftover.Confidence? {
            guard let id else { return nil }
            return c.lowercased() == "\(id).\(suffix)" ? .high : nil
        }
        // ByHost prefs are `<id>.<hostUUID>.plist`; classify the id part with the
        // trailing host component dropped so the app's own per-host prefs stay high.
        func byHost(_ c: String) -> AppLeftover.Confidence? {
            let base = strip(c, "plist")
            let withoutHost = base.contains(".") ? String(base[..<base.lastIndex(of: ".")!]) : base
            let hits = [classify(base), classify(withoutHost)]
            if hits.contains(.high) { return .high }
            if hits.contains(.medium) { return .medium }
            return nil
        }
        // Group containers: `<teamID>.<bundleID>` (or the bare id). Always medium
        // — a group container is shared across a developer's apps. Never match a
        // bare team id, and never one that belongs to another installed app.
        func groupMatch(_ c: String) -> AppLeftover.Confidence? {
            guard let id else { return nil }
            let lc = c.lowercased()
            if others.contains(where: { lc.hasSuffix("." + $0) || lc == $0 }) { return nil }
            return (lc == id || lc.hasSuffix("." + id)) ? .medium : nil
        }
        // Bundle-id directory (high, exact only) else app-name directory
        // (medium, opt-in). Exact-id folders can't collide with a sibling app.
        func idOrName(_ c: String) -> AppLeftover.Confidence? {
            let lc = c.lowercased()
            if lc == id { return .high }
            if let nameToken, lc == nameToken { return .medium }
            return nil
        }

        return [
            Search(root: root("Application Support"),     kind: .applicationSupport, match: idOrName),
            Search(root: root("Caches"),                  kind: .caches,             match: idOrName),
            Search(root: root("Logs"),                    kind: .logs,               match: idOrName),
            Search(root: root("Preferences"),             kind: .preferences,        match: { classify(strip($0, "plist")) }),
            Search(root: root("Preferences/ByHost"),      kind: .preferences,        match: byHost),
            Search(root: root("SyncedPreferences"),       kind: .preferences,        match: { idFile("plist", $0) }),
            Search(root: root("Containers"),              kind: .containers,         match: { classify($0) }),
            Search(root: root("Group Containers"),        kind: .groupContainers,    match: groupMatch),
            Search(root: root("Saved Application State"), kind: .savedState,         match: { idFile("savedstate", $0) }),
            Search(root: root("HTTPStorages"),            kind: .httpStorages,       match: { classify(strip($0, "binarycookies")) }),
            Search(root: root("WebKit"),                  kind: .webKit,             match: { classify($0) }),
            Search(root: root("Cookies"),                 kind: .cookies,            match: { idFile("binarycookies", $0) }),
            Search(root: root("Application Scripts"),     kind: .applicationScripts, match: { classify($0) }),
            Search(root: root("LaunchAgents"),            kind: .launchAgents,       match: { classify(strip($0, "plist")) }),
        ]
    }

    /// A usable, specific app-name token for heuristic matching, or `nil` when
    /// the name is too short/generic to match safely (avoids collisions like a
    /// folder literally named "Update" or "Helper").
    static func nameToken(for name: String) -> String? {
        let token = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard token.count >= 3 else { return nil }
        let generic: Set<String> = [
            "app", "data", "cache", "caches", "logs", "support", "update", "updater",
            "helper", "player", "service", "agent", "daemon", "installer",
            "uninstaller", "launcher", "tools", "utility", "utilities", "common", "shared",
        ]
        return generic.contains(token) ? nil : token
    }
}
