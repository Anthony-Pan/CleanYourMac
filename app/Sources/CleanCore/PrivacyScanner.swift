import Foundation

/// Finds browser privacy traces (caches, history, cookies, sessions, download
/// lists) under `~/Library` and, on request, moves the selected ones to the
/// Trash.
///
/// Safety and scope:
///
///  * Scanning is read-only. Removal is routed through the shared `Cleaner`/
///    `SafetyPolicy` gate, whose allowlist is exactly the parent directories of
///    the items found — so a trace can only be trashed if it sits directly
///    inside a location we deliberately looked in.
///  * The set of locations is a fixed, reviewable table below. We never touch
///    saved passwords (`Login Data`, `logins.json`, `key4.db`), autofill/cards
///    (`Web Data`), or bookmarks (`Bookmarks`, Firefox `places.sqlite`) — those
///    hold the user's own content, not disposable traces.
///  * Everything goes to the Trash, so any clear is fully recoverable.
///
/// Note: Safari's data lives under a location that requires Full Disk Access on
/// modern macOS. Without it, Safari simply yields no items (the files aren't
/// readable) — the UI surfaces a hint rather than failing.
public struct PrivacyScanner {
    /// The `~/Library` base to search. Injectable so tests can point it at a
    /// sandbox instead of the real home.
    public let libraryURL: URL
    public let disposer: FileDisposer

    public init(
        libraryURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library"),
        disposer: FileDisposer = TrashDisposer()
    ) {
        self.libraryURL = libraryURL
        self.disposer = disposer
    }

    // MARK: - Scanning (read-only)

    /// Every browser with at least one non-empty trace, largest total first.
    public func scan() -> [PrivacyGroup] {
        PrivacyApp.allCases
            .map { PrivacyGroup(app: $0, items: items(for: $0)) }
            .filter { !$0.items.isEmpty }
            .sorted { $0.totalBytes > $1.totalBytes }
    }

    /// The concrete traces for one browser, skipping anything missing or empty.
    public func items(for app: PrivacyApp) -> [PrivacyItem] {
        switch app {
        case .firefox: return firefoxItems()
        case .safari:  return safariItems()
        default:       return chromiumItems(for: app)
        }
    }

    // MARK: - Chromium family (Chrome / Edge / Brave / Vivaldi)

    /// Application-Support and Caches sub-path for each Chromium browser.
    private static func chromiumVendor(_ app: PrivacyApp) -> String? {
        switch app {
        case .chrome:  return "Google/Chrome"
        case .edge:    return "Microsoft Edge"
        case .brave:   return "BraveSoftware/Brave-Browser"
        case .vivaldi: return "Vivaldi"
        default:       return nil
        }
    }

    private func chromiumItems(for app: PrivacyApp) -> [PrivacyItem] {
        guard let vendor = Self.chromiumVendor(app) else { return [] }
        let profile = libraryURL
            .appendingPathComponent("Application Support")
            .appendingPathComponent(vendor)
            .appendingPathComponent("Default")
        let cache = libraryURL.appendingPathComponent("Caches").appendingPathComponent(vendor)

        var out: [PrivacyItem] = []
        add(&out, app, .caches, cache)

        let history = profile.appendingPathComponent("History")
        if add(&out, app, .history, history) { addSidecars(&out, app, .history, of: history) }

        // Newer Chromium keeps cookies under Default/Network; older builds under Default.
        let networkCookies = profile.appendingPathComponent("Network/Cookies")
        let legacyCookies = profile.appendingPathComponent("Cookies")
        if add(&out, app, .cookies, networkCookies) {
            addSidecars(&out, app, .cookies, of: networkCookies)
        } else if add(&out, app, .cookies, legacyCookies) {
            addSidecars(&out, app, .cookies, of: legacyCookies)
        }

        add(&out, app, .sessions, profile.appendingPathComponent("Sessions"))
        return out
    }

    // MARK: - Firefox

    private func firefoxItems() -> [PrivacyItem] {
        let profilesRoot = libraryURL
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Firefox/Profiles")
        let fm = FileManager.default
        var out: [PrivacyItem] = []

        // Cache is stored per-Firefox (not per-profile path we walk), one item.
        add(&out, .firefox, .caches, libraryURL.appendingPathComponent("Caches/Firefox"))

        let profiles = (try? fm.contentsOfDirectory(at: profilesRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for profile in profiles {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: profile.path, isDirectory: &isDir), isDir.boolValue else { continue }
            // History lives in places.sqlite alongside BOOKMARKS — never offered.
            let cookies = profile.appendingPathComponent("cookies.sqlite")
            if add(&out, .firefox, .cookies, cookies) { addSidecars(&out, .firefox, .cookies, of: cookies) }
            add(&out, .firefox, .sessions, profile.appendingPathComponent("sessionstore.jsonlz4"))
            add(&out, .firefox, .sessions, profile.appendingPathComponent("sessionstore-backups"))
        }
        return out
    }

    // MARK: - Safari (requires Full Disk Access)

    private func safariItems() -> [PrivacyItem] {
        let safari = libraryURL.appendingPathComponent("Safari")
        var out: [PrivacyItem] = []
        add(&out, .safari, .caches, libraryURL.appendingPathComponent("Caches/com.apple.Safari"))
        let history = safari.appendingPathComponent("History.db")
        if add(&out, .safari, .history, history) { addSidecars(&out, .safari, .history, of: history) }
        add(&out, .safari, .downloads, safari.appendingPathComponent("Downloads.plist"))
        return out
    }

    // MARK: - Helpers

    /// File names that must NEVER be offered, matched case-insensitively. These
    /// hold the user's own content — saved passwords, autofill/cards, and
    /// bookmarks (including the Firefox `places.sqlite` that stores history *and*
    /// bookmarks together). Defense in depth: the search tables above already
    /// avoid these paths, but this guard guarantees that even a future edit to
    /// those tables can never turn one of them into a removable item.
    private static let neverRemoveBasenames: Set<String> = [
        // Saved passwords / credentials.
        "login data", "login data-journal",
        "login data for account", "login data for account-journal",
        "logins.json", "logins-backup.json", "key3.db", "key4.db",
        // Autofill, payment cards, and other saved form data.
        "web data", "web data-journal",
        // Bookmarks, and the Firefox DB that also stores them alongside history.
        "bookmarks", "bookmarks.bak",
        "places.sqlite", "places.sqlite-wal", "places.sqlite-shm",
    ]

    /// Append a `PrivacyItem` if `url` exists, has non-zero size, and is not on
    /// the never-remove list. Returns whether an item was added (used to pick
    /// the first of alternative paths).
    @discardableResult
    private func add(_ out: inout [PrivacyItem], _ app: PrivacyApp, _ kind: PrivacyItemKind, _ url: URL) -> Bool {
        guard !Self.neverRemoveBasenames.contains(url.lastPathComponent.lowercased()) else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = Scanner.allocatedSize(of: url)
        guard size > 0 else { return false }
        out.append(PrivacyItem(app: app, kind: kind, url: url, sizeBytes: size))
        return true
    }

    /// SQLite databases run in WAL mode, so on disk each is the primary file plus
    /// `-wal`/`-shm` (and occasionally `-journal`) sidecars holding rows not yet
    /// checkpointed into the main file. Clearing only the primary file would
    /// leave recent history/cookies readable in the orphaned sidecar — the exact
    /// data the user asked to erase — so we clear them together. Each sidecar
    /// sits beside its database inside an already-allowed root.
    private func addSidecars(_ out: inout [PrivacyItem], _ app: PrivacyApp, _ kind: PrivacyItemKind, of dbURL: URL) {
        let dir = dbURL.deletingLastPathComponent()
        let base = dbURL.lastPathComponent
        for suffix in ["-wal", "-shm", "-journal"] {
            add(&out, app, kind, dir.appendingPathComponent(base + suffix))
        }
    }

    // MARK: - Removal

    /// Move the given traces to the Trash (or, in `dryRun`, report what *would*
    /// happen). Every path is re-validated by the shared `Cleaner`/`SafetyPolicy`
    /// gate immediately before disposal.
    public func clear(_ items: [PrivacyItem], dryRun: Bool) -> CleanReport {
        let policy = SafetyPolicy(allowedRoots: allowedRoots())
        let scanItems = items.map {
            ScanItem(url: $0.url, categoryID: "privacy-\($0.app.rawValue)", sizeBytes: $0.sizeBytes, modificationDate: nil)
        }
        return Cleaner(policy: policy, disposer: disposer).clean(scanItems, dryRun: dryRun)
    }

    /// The fixed, declarative set of directories whose contents the Privacy
    /// cleaner is ever allowed to touch — the known browser-data locations,
    /// **independent of what was found**. A trace can only be removed if it
    /// lives strictly inside one of these; anything else (a stale item, a
    /// crafted path, a bug) is refused by the safety gate.
    ///
    /// Critically, this is *not* derived from the items being cleared — doing so
    /// would let any item define its own allowed root and defeat the gate. The
    /// Firefox profile directories are the one dynamic part, and they are read
    /// from the real on-disk layout, never from item paths.
    func allowedRoots() -> [URL] {
        let fm = FileManager.default
        let caches = libraryURL.appendingPathComponent("Caches")
        let appSupport = libraryURL.appendingPathComponent("Application Support")

        // All browser caches live directly under ~/Library/Caches. This is the
        // one broad root, and it is cache-only — it never contains documents.
        var roots: [URL] = [caches]

        // Chromium profile directories (history/cookies/sessions live here).
        for vendor in ["Google/Chrome", "Microsoft Edge", "BraveSoftware/Brave-Browser", "Vivaldi"] {
            let def = appSupport.appendingPathComponent(vendor).appendingPathComponent("Default")
            roots.append(def)
            roots.append(def.appendingPathComponent("Network"))   // modern cookies location
        }

        // Firefox: each real profile directory (dynamic names, read from disk).
        let ffProfiles = appSupport.appendingPathComponent("Firefox/Profiles")
        let profiles = (try? fm.contentsOfDirectory(
            at: ffProfiles, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        roots.append(contentsOf: profiles)

        // Safari (History.db / Downloads.plist live directly under ~/Library/Safari).
        roots.append(libraryURL.appendingPathComponent("Safari"))

        return roots
    }
}
