import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Finds browser, app, and macOS privacy traces (caches, history, cookies,
/// sessions, download lists, site data, recent items, plus Chromium-embedded
/// app traces and system-wide traces via the composed `ElectronTraceScanner`
/// and `SystemTraceScanner`) and, on request, moves the selected ones to the
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
///  * Defense in depth: `clear(_:dryRun:)` re-validates every item's basename
///    against the never-remove list before handing it to the `Cleaner` gate.
///
/// Note: Safari's data lives under a location that requires Full Disk Access on
/// modern macOS. Without it, Safari simply yields no items (the files aren't
/// readable) — the VM detects this and surfaces a hint banner.
public struct PrivacyScanner {
    /// The `~/Library` base to search. Injectable so tests can point it at a
    /// sandbox instead of the real home.
    public let libraryURL: URL
    /// The home directory holding shell history files. Defaults to the parent
    /// of `libraryURL`, so a sandboxed library implies a sandboxed home.
    public let homeURL: URL
    /// The per-user Darwin cache directory (QuickLook thumbnails live there).
    /// `nil` by default — only `production()` supplies the real location, so
    /// tests can never reach the real cache by accident.
    public let darwinCacheURL: URL?
    public let disposer: FileDisposer

    public init(
        libraryURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library"),
        homeURL: URL? = nil,
        darwinCacheURL: URL? = nil,
        disposer: FileDisposer = TrashDisposer()
    ) {
        self.libraryURL = libraryURL
        self.homeURL = homeURL ?? libraryURL.deletingLastPathComponent()
        self.darwinCacheURL = darwinCacheURL
        self.disposer = disposer
    }

    /// The scanner the real app uses: the default real `~/Library`/home plus
    /// the real per-user Darwin cache directory, resolved via
    /// `confstr(_CS_DARWIN_USER_CACHE_DIR)`.
    public static func production() -> PrivacyScanner {
        PrivacyScanner(darwinCacheURL: darwinUserCacheDirectory())
    }

    /// Resolves `confstr(_CS_DARWIN_USER_CACHE_DIR)` (e.g. `/var/folders/…/C/`),
    /// or `nil` when the system refuses to answer.
    private static func darwinUserCacheDirectory() -> URL? {
        let length = confstr(_CS_DARWIN_USER_CACHE_DIR, nil, 0)
        guard length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, length) == length else { return nil }
        let path = String(cString: buffer)
        return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
    }

    // MARK: - Composed sub-scanners

    private var electronScanner: ElectronTraceScanner {
        ElectronTraceScanner(libraryURL: libraryURL)
    }

    private var systemScanner: SystemTraceScanner {
        SystemTraceScanner(libraryURL: libraryURL, homeURL: homeURL, darwinCacheURL: darwinCacheURL)
    }

    // MARK: - Scanning (read-only)

    /// Every browser/app/subsystem with at least one non-empty trace, largest
    /// total first: the known browsers, macOS Recent Items, signature-detected
    /// Chromium-embedded apps, and system-wide macOS traces.
    public func scan() -> [PrivacyGroup] {
        let fixedGroups = (PrivacyApp.browsers + [.systemRecents])
            .map { PrivacyGroup(app: $0, items: items(for: $0)) }
        return (fixedGroups + electronScanner.groups() + systemScanner.groups())
            .filter { !$0.items.isEmpty }
            .sorted { $0.totalBytes > $1.totalBytes }
    }

    /// The concrete traces for one browser, app, or macOS subsystem, skipping
    /// anything missing or empty.
    public func items(for app: PrivacyApp) -> [PrivacyItem] {
        switch app {
        case .firefox:       return firefoxItems()
        case .safari:        return safariItems()
        case .systemRecents: return systemRecentsItems()
        case .electron:
            return electronScanner.groups().first { $0.app == app }?.items ?? []
        case .quickLook, .savedState, .quarantine, .shellHistory, .diagnostics:
            return systemScanner.groups().first { $0.app == app }?.items ?? []
        default:             return chromiumItems(for: app)
        }
    }

    // MARK: - Chromium family

    /// Declarative description of one Chromium-family vendor's on-disk layout.
    private struct ChromiumVendor {
        /// Sub-paths relative to `~/Library/Application Support` — one per
        /// release channel. Each is scanned independently.
        let appSupportSubpaths: [String]
        /// Sub-paths relative to `~/Library` for the browser's cache directories.
        let cacheSubpaths: [String]
        /// True for vendors (Opera, Opera GX) whose profile files live directly
        /// in the vendor directory rather than inside a `Default/` subdirectory.
        let flatProfile: Bool
    }

    /// The fixed, reviewable per-vendor layout table. Only paths listed here can
    /// ever be scanned or removed — adding a new browser means editing this table.
    private static func chromiumVendors(for app: PrivacyApp) -> ChromiumVendor? {
        switch app {
        case .chrome:
            return ChromiumVendor(
                appSupportSubpaths: [
                    "Google/Chrome",
                    "Google/Chrome Beta",
                    "Google/Chrome Dev",
                    "Google/Chrome Canary",
                ],
                cacheSubpaths: [
                    "Caches/Google/Chrome",
                    "Caches/Google/Chrome Beta",
                    "Caches/Google/Chrome Dev",
                    "Caches/Google/Chrome Canary",
                ],
                flatProfile: false
            )
        case .edge:
            return ChromiumVendor(
                appSupportSubpaths: [
                    "Microsoft Edge",
                    "Microsoft Edge Beta",
                    "Microsoft Edge Dev",
                    "Microsoft Edge Canary",
                ],
                cacheSubpaths: [
                    "Caches/Microsoft Edge",
                    "Caches/Microsoft Edge Beta",
                    "Caches/Microsoft Edge Dev",
                    "Caches/Microsoft Edge Canary",
                ],
                flatProfile: false
            )
        case .brave:
            return ChromiumVendor(
                appSupportSubpaths: [
                    "BraveSoftware/Brave-Browser",
                    "BraveSoftware/Brave-Browser-Beta",
                    "BraveSoftware/Brave-Browser-Nightly",
                ],
                cacheSubpaths: [
                    "Caches/BraveSoftware/Brave-Browser",
                    "Caches/BraveSoftware/Brave-Browser-Beta",
                    "Caches/BraveSoftware/Brave-Browser-Nightly",
                ],
                flatProfile: false
            )
        case .vivaldi:
            return ChromiumVendor(
                appSupportSubpaths: ["Vivaldi"],
                cacheSubpaths: ["Caches/Vivaldi"],
                flatProfile: false
            )
        case .arc:
            // Arc uses standard Chromium layout inside `Arc/User Data`.
            // It may write its disk cache to either (or both) of two locations.
            return ChromiumVendor(
                appSupportSubpaths: ["Arc/User Data"],
                cacheSubpaths: [
                    "Caches/Arc",
                    "Caches/company.thebrowser.Browser",
                ],
                flatProfile: false
            )
        case .chromium:
            return ChromiumVendor(
                appSupportSubpaths: ["Chromium"],
                cacheSubpaths: ["Caches/Chromium"],
                flatProfile: false
            )
        case .opera:
            // Opera uses a flat layout: profile files live directly in the
            // vendor directory (no `Default/` subdirectory).
            return ChromiumVendor(
                appSupportSubpaths: ["com.operasoftware.Opera"],
                cacheSubpaths: ["Caches/com.operasoftware.Opera"],
                flatProfile: true
            )
        case .operaGX:
            return ChromiumVendor(
                appSupportSubpaths: ["com.operasoftware.OperaGX"],
                cacheSubpaths: ["Caches/com.operasoftware.OperaGX"],
                flatProfile: true
            )
        default:
            return nil
        }
    }

    /// Returns all real profile directories inside `vendorDir`: `Default` plus
    /// any directory whose name starts with `Profile `. The list is read from the
    /// real filesystem, following the same sanctioned precedent as Firefox profile
    /// enumeration. Results are sorted `Default` first, then alphabetically.
    private static func chromiumProfiles(
        in vendorDir: URL,
        fm: FileManager = .default
    ) -> [(url: URL, name: String)] {
        let entries = (try? fm.contentsOfDirectory(
            at: vendorDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var profiles: [(url: URL, name: String)] = []
        for entry in entries {
            let name = entry.lastPathComponent
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            if name == "Default" || name.hasPrefix("Profile ") {
                profiles.append((entry, name))
            }
        }

        return profiles.sorted { a, b in
            if a.name == "Default" { return true }
            if b.name == "Default" { return false }
            return a.name < b.name
        }
    }

    private func chromiumItems(for app: PrivacyApp) -> [PrivacyItem] {
        guard let vendor = Self.chromiumVendors(for: app) else { return [] }
        let appSupport = libraryURL.appendingPathComponent("Application Support")
        var out: [PrivacyItem] = []

        // Per-vendor cache directories (all under ~/Library/Caches).
        for cachePath in vendor.cacheSubpaths {
            add(&out, app, .caches, libraryURL.appendingPathComponent(cachePath))
        }

        // Scan each release-channel directory.
        for subpath in vendor.appSupportSubpaths {
            let vendorDir = appSupport.appendingPathComponent(subpath)

            if vendor.flatProfile {
                // Opera / Opera GX: vendor directory is the profile root.
                scanChromiumProfile(into: &out, app: app, profileDir: vendorDir, context: nil)
            } else {
                // Standard Chromium layout: Default + Profile N.
                let profiles = Self.chromiumProfiles(in: vendorDir)
                for profile in profiles {
                    // Non-Default profiles get a context badge in the UI.
                    let ctx: String? = profile.name == "Default" ? nil : profile.name
                    scanChromiumProfile(into: &out, app: app, profileDir: profile.url, context: ctx)
                }
            }
        }

        return out
    }

    /// Scans one Chromium profile directory for all supported trace kinds.
    private func scanChromiumProfile(
        into out: inout [PrivacyItem],
        app: PrivacyApp,
        profileDir: URL,
        context: String?
    ) {
        // ── History and related visit/UI data ──────────────────────────────
        let history = profileDir.appendingPathComponent("History")
        if add(&out, app, .history, history, context: context) {
            addSidecars(&out, app, .history, of: history, context: context)
        }
        add(&out, app, .history, profileDir.appendingPathComponent("Visited Links"), context: context)

        let topSites = profileDir.appendingPathComponent("Top Sites")
        if add(&out, app, .history, topSites, context: context) {
            addSidecars(&out, app, .history, of: topSites, context: context)
        }

        let shortcuts = profileDir.appendingPathComponent("Shortcuts")
        if add(&out, app, .history, shortcuts, context: context) {
            addSidecars(&out, app, .history, of: shortcuts, context: context)
        }

        let mediaHistory = profileDir.appendingPathComponent("Media History")
        if add(&out, app, .history, mediaHistory, context: context) {
            addSidecars(&out, app, .history, of: mediaHistory, context: context)
        }

        let predictor = profileDir.appendingPathComponent("Network Action Predictor")
        if add(&out, app, .history, predictor, context: context) {
            addSidecars(&out, app, .history, of: predictor, context: context)
        }

        let favicons = profileDir.appendingPathComponent("Favicons")
        if add(&out, app, .history, favicons, context: context) {
            addSidecars(&out, app, .history, of: favicons, context: context)
        }

        // ── Cookies — modern (Network/Cookies) or legacy (Cookies) ────────
        let networkCookies = profileDir.appendingPathComponent("Network/Cookies")
        let legacyCookies  = profileDir.appendingPathComponent("Cookies")
        if add(&out, app, .cookies, networkCookies, context: context) {
            addSidecars(&out, app, .cookies, of: networkCookies, context: context)
        } else if add(&out, app, .cookies, legacyCookies, context: context) {
            addSidecars(&out, app, .cookies, of: legacyCookies, context: context)
        }

        // ── Session / tab state ────────────────────────────────────────────
        add(&out, app, .sessions, profileDir.appendingPathComponent("Sessions"), context: context)
        // Legacy single-file session formats (older Chromium builds).
        for name in ["Current Session", "Last Session", "Current Tabs", "Last Tabs"] {
            add(&out, app, .sessions, profileDir.appendingPathComponent(name), context: context)
        }

        // ── Per-profile caches ─────────────────────────────────────────────
        add(&out, app, .caches, profileDir.appendingPathComponent("GPUCache"), context: context)
        add(&out, app, .caches, profileDir.appendingPathComponent("Code Cache"), context: context)

        // ── Site data (opt-in — clearing may sign the user out) ────────────
        for name in ["Local Storage", "Session Storage", "IndexedDB", "Service Worker"] {
            add(&out, app, .siteData, profileDir.appendingPathComponent(name), context: context)
        }
    }

    // MARK: - Firefox

    private func firefoxItems() -> [PrivacyItem] {
        let profilesRoot = libraryURL
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Firefox/Profiles")
        let fm = FileManager.default
        var out: [PrivacyItem] = []

        // Cache is stored per-Firefox-install, outside per-profile directories.
        add(&out, .firefox, .caches, libraryURL.appendingPathComponent("Caches/Firefox"))

        let allEntries = (try? fm.contentsOfDirectory(
            at: profilesRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        // Only actual profile directories (not stray files).
        let profiles = allEntries.filter { url in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }

        // Show the profile folder name as a context badge only when there is
        // more than one profile, following the same sanctioned pattern as
        // Chromium multi-profile enumeration.
        let useContext = profiles.count > 1

        for profile in profiles {
            let ctx: String? = useContext ? profile.lastPathComponent : nil

            // Cookies database and its SQLite sidecars.
            let cookies = profile.appendingPathComponent("cookies.sqlite")
            if add(&out, .firefox, .cookies, cookies, context: ctx) {
                addSidecars(&out, .firefox, .cookies, of: cookies, context: ctx)
            }

            // Session state.
            add(&out, .firefox, .sessions,
                profile.appendingPathComponent("sessionstore.jsonlz4"), context: ctx)
            add(&out, .firefox, .sessions,
                profile.appendingPathComponent("sessionstore-backups"), context: ctx)

            // Site data: offline web app store and per-origin storage.
            let webappsStore = profile.appendingPathComponent("webappsstore.sqlite")
            if add(&out, .firefox, .siteData, webappsStore, context: ctx) {
                addSidecars(&out, .firefox, .siteData, of: webappsStore, context: ctx)
            }
            add(&out, .firefox, .siteData, profile.appendingPathComponent("storage"), context: ctx)
        }

        return out
    }

    // MARK: - Safari (requires Full Disk Access)

    private func safariItems() -> [PrivacyItem] {
        let safari = libraryURL.appendingPathComponent("Safari")
        var out: [PrivacyItem] = []

        // Browser-level cache and per-session favicon cache.
        add(&out, .safari, .caches, libraryURL.appendingPathComponent("Caches/com.apple.Safari"))
        add(&out, .safari, .caches, safari.appendingPathComponent("Favicon Cache"))

        // History database (plus SQLite sidecars) and Top Sites list.
        let history = safari.appendingPathComponent("History.db")
        if add(&out, .safari, .history, history) { addSidecars(&out, .safari, .history, of: history) }
        add(&out, .safari, .history, safari.appendingPathComponent("TopSites.plist"))

        // Download history (the record, not the downloaded files themselves).
        add(&out, .safari, .downloads, safari.appendingPathComponent("Downloads.plist"))

        // Session / tab state restored on next launch.
        add(&out, .safari, .sessions, safari.appendingPathComponent("LastSession.plist"))
        add(&out, .safari, .sessions, safari.appendingPathComponent("RecentlyClosedTabs.plist"))

        // Cookies — stored inside Safari's App Sandbox container. Requires FDA.
        let containerCookies = libraryURL
            .appendingPathComponent("Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies")
        add(&out, .safari, .cookies, containerCookies)

        // Site data stored per-origin by WebKit.
        add(&out, .safari, .siteData, safari.appendingPathComponent("LocalStorage"))
        add(&out, .safari, .siteData, safari.appendingPathComponent("Databases"))

        return out
    }

    // MARK: - macOS Recent Items

    /// Scans the shared-file-list directory that macOS uses to maintain the
    /// recent-documents, recent-applications, and recent-servers menus. The sfl2/
    /// sfl3 extension varies by macOS version — we match by filename prefix so
    /// the scanner is robust across versions.
    private func systemRecentsItems() -> [PrivacyItem] {
        let sharedFileLists = libraryURL
            .appendingPathComponent("Application Support")
            .appendingPathComponent("com.apple.sharedfilelist")
        var out: [PrivacyItem] = []

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: sharedFileLists,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for entry in entries {
            let name = entry.lastPathComponent
            if name.hasPrefix("com.apple.LSSharedFileList.RecentDocuments") {
                add(&out, .systemRecents, .recentDocuments, entry)
            } else if name.hasPrefix("com.apple.LSSharedFileList.RecentApplications") {
                add(&out, .systemRecents, .recentApplications, entry)
            } else if name.hasPrefix("com.apple.LSSharedFileList.RecentServers") ||
                      name.hasPrefix("com.apple.LSSharedFileList.RecentHosts") {
                add(&out, .systemRecents, .recentServers, entry)
            } else if name == "ApplicationRecentDocuments" ||
                      name.hasPrefix("com.apple.LSSharedFileList.ApplicationRecentDocuments") {
                // The entire per-app recent-files directory as a single item —
                // clearing it is atomic and avoids partial state. macOS 26+
                // prefixes the directory name with the shared-file-list domain.
                add(&out, .systemRecents, .appRecents, entry)
            }
        }

        return out
    }

    // MARK: - Helpers

    /// File basenames that must NEVER be offered, compared case-insensitively
    /// after normalisation (see `normalizeBasename`). These hold the user's own
    /// content — saved passwords, autofill/cards, and bookmarks (including the
    /// Firefox `places.sqlite` that stores history *and* bookmarks together).
    ///
    /// Defense in depth: the search tables above already avoid these paths, but
    /// this guard guarantees that even a future edit to those tables can never
    /// turn one of them into a removable item. `clear(_:dryRun:)` applies a
    /// second check against this set before passing items to the Cleaner gate.
    /// Internal (not private) because every composed sub-scanner enforces it too.
    static let neverRemoveBasenames: Set<String> = [
        // Saved passwords / credentials.
        "login data", "login data-journal",
        "login data for account", "login data for account-journal",
        "logins.json", "logins-backup.json", "key3.db", "key4.db",
        // Autofill, payment cards, and other saved form data.
        "web data", "web data-journal",
        // Safari autofill database.
        "form values",
        // Browser configuration stores. Never traces — and for the flat-profile
        // vendors (Opera/Opera GX) they sit directly inside an allowed root, so
        // the denylist is what keeps a crafted item away from them.
        "preferences", "secure preferences", "local state",
        "prefs.js", "user.js",
        // Firefox autofill, permissions, and credential stores.
        "formhistory.sqlite", "signons.sqlite",
        "cert8.db", "cert9.db", "permissions.sqlite",
        // Bookmarks, and the Firefox DB that also stores them alongside history.
        "bookmarks", "bookmarks.bak",
        "places.sqlite", "places.sqlite-wal", "places.sqlite-shm",
        // Firefox favicons database — embedded within places and tied to bookmarks.
        "favicons.sqlite",
    ]

    /// Returns the canonical form used for denylist comparison: lowercased with
    /// every trailing SQLite journal suffix (`-wal`, `-shm`, `-journal`) removed,
    /// so `Login Data-wal` — and even a crafted `Login Data-wal-shm` — is treated
    /// identically to `Login Data`. Stripping loops until no suffix remains so a
    /// stacked-suffix name can never slip past the denylist.
    static func normalizeBasename(_ name: String) -> String {
        var s = name.lowercased()
        var stripped = true
        while stripped {
            stripped = false
            for suffix in ["-wal", "-shm", "-journal"] where s.hasSuffix(suffix) {
                s = String(s.dropLast(suffix.count))
                stripped = true
                break
            }
        }
        return s
    }

    /// Append a `PrivacyItem` if `url` exists, has non-zero size, and is not on
    /// the never-remove list. Returns whether an item was added (used to pick
    /// the first of alternative paths).
    @discardableResult
    private func add(
        _ out: inout [PrivacyItem],
        _ app: PrivacyApp,
        _ kind: PrivacyItemKind,
        _ url: URL,
        context: String? = nil
    ) -> Bool {
        guard !Self.neverRemoveBasenames.contains(
            Self.normalizeBasename(url.lastPathComponent)
        ) else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = Scanner.allocatedSize(of: url)
        guard size > 0 else { return false }
        out.append(PrivacyItem(app: app, kind: kind, url: url, sizeBytes: size, context: context))
        return true
    }

    /// SQLite databases run in WAL mode, so on disk each is the primary file plus
    /// `-wal`/`-shm` (and occasionally `-journal`) sidecars holding rows not yet
    /// checkpointed into the main file. Clearing only the primary file would
    /// leave recent history/cookies readable in the orphaned sidecar — the exact
    /// data the user asked to erase — so we clear them together. Each sidecar
    /// sits beside its database inside an already-allowed root.
    private func addSidecars(
        _ out: inout [PrivacyItem],
        _ app: PrivacyApp,
        _ kind: PrivacyItemKind,
        of dbURL: URL,
        context: String? = nil
    ) {
        let dir = dbURL.deletingLastPathComponent()
        let base = dbURL.lastPathComponent
        for suffix in ["-wal", "-shm", "-journal"] {
            add(&out, app, kind, dir.appendingPathComponent(base + suffix), context: context)
        }
    }

    // MARK: - Removal

    /// Move the given traces to the Trash (or, in `dryRun`, report what *would*
    /// happen). Every path is validated in three stages:
    ///
    ///  1. Pre-flight denylist check (this method): any item whose normalised
    ///     basename is on the never-remove list is blocked with `.protectedContent`
    ///     before reaching the Cleaner — defense in depth against stale or crafted
    ///     `PrivacyItem` values.
    ///  2. Structural check (this method): any item located *inside* a detected
    ///     Electron root may only name one of the fixed electron trace entries.
    ///     The check is keyed on the item's real location, not its self-declared
    ///     `app`, so a mislabeled or crafted item pointing at app content inside
    ///     a detected root cannot bypass it. Anything else is blocked with
    ///     `.protectedContent`.
    ///  3. `SafetyPolicy` gate (inside `Cleaner`): every remaining item must live
    ///     strictly inside a declared allowed root or be a declared exact target.
    public func clear(_ items: [PrivacyItem], dryRun: Bool) -> CleanReport {
        var report = CleanReport(dryRun: dryRun)
        var safeItems: [PrivacyItem] = []

        // Detected Electron roots are whole app directories that also hold app
        // content and config; the trace-name allowlist is what keeps everything
        // else in them off-limits. Keyed on location, so attribution can't lie.
        let electronRoots = electronScanner.detectedRoots().map { $0.canonicalized }

        for item in items {
            let normalized = Self.normalizeBasename(item.url.lastPathComponent)
            let target = item.url.canonicalized
            let insideElectronRoot = electronRoots.contains { $0.isStrictAncestor(of: target) }
            if Self.neverRemoveBasenames.contains(normalized) {
                report.blocked.append(
                    SafetyRejection(reason: .protectedContent, path: item.url.path)
                )
            } else if insideElectronRoot,
                      !ElectronTraceScanner.electronTraceBasenames.contains(normalized) {
                report.blocked.append(
                    SafetyRejection(reason: .protectedContent, path: item.url.path)
                )
            } else {
                safeItems.append(item)
            }
        }

        let policy = SafetyPolicy(allowedRoots: allowedRoots(), allowedExactTargets: exactTargets())
        let scanItems = safeItems.map {
            ScanItem(url: $0.url, categoryID: "privacy-\($0.app.key)",
                     sizeBytes: $0.sizeBytes, modificationDate: nil)
        }
        let inner = Cleaner(policy: policy, disposer: disposer).clean(scanItems, dryRun: dryRun)

        report.trashed   = inner.trashed
        report.blocked  += inner.blocked
        report.failed    = inner.failed
        report.freedBytes = inner.freedBytes

        return report
    }

    /// The fixed, declarative set of directories whose contents the Privacy
    /// cleaner is ever allowed to touch — the known browser-data locations,
    /// **independent of what was found**. A trace can only be removed if it
    /// lives strictly inside one of these; anything else (a stale item, a
    /// crafted path, a bug) is refused by the safety gate.
    ///
    /// Critically, this is *not* derived from the items being cleared — doing so
    /// would let any item define its own allowed root and defeat the gate. The
    /// Chromium and Firefox profile directories are the one dynamic part, and they
    /// are read from the real on-disk layout, never from item paths.
    func allowedRoots() -> [URL] {
        let fm = FileManager.default
        let caches    = libraryURL.appendingPathComponent("Caches")
        let appSupport = libraryURL.appendingPathComponent("Application Support")

        // All browser caches live directly under ~/Library/Caches. This is the
        // one broad root, and it is cache-only — it never contains documents.
        var roots: [URL] = [caches]

        // Standard Chromium-family vendors: enumerate real profile directories
        // (Default + Profile N) from disk for each release channel, add each
        // profile dir plus its Network subdir (modern cookie location).
        let standardChromiumApps: [PrivacyApp] = [.chrome, .edge, .brave, .vivaldi, .arc, .chromium]
        for app in standardChromiumApps {
            guard let vendor = Self.chromiumVendors(for: app) else { continue }
            for subpath in vendor.appSupportSubpaths {
                let vendorDir = appSupport.appendingPathComponent(subpath)
                for profile in Self.chromiumProfiles(in: vendorDir, fm: fm) {
                    roots.append(profile.url)
                    roots.append(profile.url.appendingPathComponent("Network"))
                }
            }
        }

        // Flat-profile Chromium vendors (Opera, Opera GX): the vendor directory
        // itself is the profile root.
        let flatChromiumApps: [PrivacyApp] = [.opera, .operaGX]
        for app in flatChromiumApps {
            guard let vendor = Self.chromiumVendors(for: app) else { continue }
            for subpath in vendor.appSupportSubpaths {
                let vendorDir = appSupport.appendingPathComponent(subpath)
                roots.append(vendorDir)
                roots.append(vendorDir.appendingPathComponent("Network"))
            }
        }

        // Firefox: each real profile directory (dynamic names, read from disk).
        let ffProfiles = appSupport.appendingPathComponent("Firefox/Profiles")
        let profiles = (try? fm.contentsOfDirectory(
            at: ffProfiles, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        roots.append(contentsOf: profiles)

        // Safari — History.db / Downloads.plist / session plists live here.
        roots.append(libraryURL.appendingPathComponent("Safari"))

        // Safari cookies are sandboxed in the app container; requires FDA.
        roots.append(
            libraryURL.appendingPathComponent("Containers/com.apple.Safari/Data/Library/Cookies")
        )

        // macOS Recent Items shared-file-list directory.
        roots.append(appSupport.appendingPathComponent("com.apple.sharedfilelist"))

        // System trace directories (Saved Application State, DiagnosticReports) —
        // fixed paths derived from libraryURL.
        roots.append(contentsOf: systemScanner.roots())

        // Signature-verified Chromium-embedded app tiers — read from the real
        // disk layout (the same sanctioned precedent as profile enumeration),
        // never from item paths.
        roots.append(contentsOf: electronScanner.detectedRoots())

        return roots
    }

    /// The fixed set of exact single-location traces the Privacy cleaner may
    /// remove *themselves* (the quarantine database, shell history files, the
    /// QuickLook cache directory). Like `allowedRoots()`, declarative — never
    /// derived from the items being cleared.
    func exactTargets() -> [URL] {
        systemScanner.exactTargets()
    }
}
