import Foundation

/// Finds system-wide macOS privacy traces: QuickLook thumbnails, saved window
/// state, download-provenance (quarantine) records, shell command history, and
/// crash/diagnostic reports.
///
/// Safety and scope:
///
///  * Every location derives from the injected `libraryURL` / `homeURL` /
///    `darwinCacheURL` bases — never from hard-coded machine paths — so test
///    sandboxes stay hermetic.
///  * Directory-shaped subsystems expose declarative roots via `roots()`;
///    fixed single-location traces (the quarantine database, shell history
///    files, the QuickLook cache directory) are `exactTargets()` — validated
///    by full-path equality in `SafetyPolicy`, even stricter than a root.
///  * Shell history and window state are disruptive → their kinds are opt-in
///    (`defaultOn == false`).
struct SystemTraceScanner {
    /// The `~/Library` base to search. Injectable for tests.
    let libraryURL: URL
    /// The home directory holding shell history files. Defaults (via
    /// `PrivacyScanner`) to the parent of `libraryURL` so sandboxes stay hermetic.
    let homeURL: URL
    /// The per-user Darwin cache directory from `confstr(_CS_DARWIN_USER_CACHE_DIR)`
    /// where QuickLook keeps its thumbnail cache. `nil` outside production so
    /// tests can never reach the real cache by accident.
    let darwinCacheURL: URL?

    // MARK: - Fixed locations

    /// Candidate QuickLook thumbnail-cache directories across macOS versions.
    /// Whichever exists (and is non-empty) is offered as a single whole-directory
    /// item. The modern path is TCC-protected — unreadable without Full Disk
    /// Access it simply yields no item.
    private var quickLookCandidates: [URL] {
        let darwin = darwinCacheURL.map {
            [
                $0.appendingPathComponent("com.apple.quicklook.ThumbnailsAgent/com.apple.QuickLook.thumbnailcache"),
                $0.appendingPathComponent("com.apple.QuickLook.thumbnailcache"),
            ]
        } ?? []
        return darwin + [
            libraryURL.appendingPathComponent(
                "Containers/com.apple.quicklook.ThumbnailsAgent/Data/Library/Caches/com.apple.QuickLook.thumbnailcache"
            ),
        ]
    }

    /// Saved window/UI state — absent on macOS 26+, present on older versions.
    private var savedStateDir: URL {
        libraryURL.appendingPathComponent("Saved Application State")
    }

    /// The quarantine ("where from") SQLite database.
    private var quarantineDB: URL {
        libraryURL.appendingPathComponent("Preferences/com.apple.LaunchServices.QuarantineEventsV2")
    }

    /// Crash and diagnostic reports.
    private var diagnosticsDir: URL {
        libraryURL.appendingPathComponent("Logs/DiagnosticReports")
    }

    /// Fixed list of shell/REPL history files, relative to the home directory.
    private static let shellHistoryFileNames = [
        ".zsh_history", ".bash_history", ".python_history",
        ".node_repl_history", ".lesshst",
    ]

    /// Per-session zsh history — one whole-directory item.
    private var zshSessionsDir: URL {
        homeURL.appendingPathComponent(".zsh_sessions")
    }

    /// Extensions of genuine crash/diagnostic reports. Only top-level files with
    /// one of these are offered — anything else a user parked in the folder is
    /// left alone, matching the documented intent.
    private static let diagnosticExtensions: Set<String> = [
        "ips", "crash", "diag", "panic", "spin", "hang", "stackshot",
        "wakeups_resource", "cpu_resource", "disk_resource", "gpurestart",
    ]

    // MARK: - Scanning (read-only)

    /// One `PrivacyGroup` per subsystem with at least one non-empty trace.
    func groups() -> [PrivacyGroup] {
        [
            PrivacyGroup(app: .quickLook, items: quickLookItems()),
            PrivacyGroup(app: .savedState, items: savedStateItems()),
            PrivacyGroup(app: .quarantine, items: quarantineItems()),
            PrivacyGroup(app: .shellHistory, items: shellHistoryItems()),
            PrivacyGroup(app: .diagnostics, items: diagnosticsItems()),
        ].filter { !$0.items.isEmpty }
    }

    private func quickLookItems() -> [PrivacyItem] {
        var out: [PrivacyItem] = []
        for candidate in quickLookCandidates {
            add(&out, .quickLook, .thumbnails, candidate)
        }
        return out
    }

    private func savedStateItems() -> [PrivacyItem] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: savedStateDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var out: [PrivacyItem] = []
        // Only the per-app `*.savedState` bundles — never stray siblings.
        for entry in entries where entry.lastPathComponent.hasSuffix(".savedState") {
            add(&out, .savedState, .windowState, entry)
        }
        return out
    }

    private func quarantineItems() -> [PrivacyItem] {
        var out: [PrivacyItem] = []
        if add(&out, .quarantine, .downloadRecords, quarantineDB) {
            addSidecars(&out, .quarantine, .downloadRecords, of: quarantineDB)
        }
        return out
    }

    private func shellHistoryItems() -> [PrivacyItem] {
        var out: [PrivacyItem] = []
        for name in Self.shellHistoryFileNames {
            add(&out, .shellHistory, .shellHistory, homeURL.appendingPathComponent(name))
        }
        // The whole per-session directory as one item — clearing it is atomic.
        add(&out, .shellHistory, .shellHistory, zshSessionsDir)
        return out
    }

    private func diagnosticsItems() -> [PrivacyItem] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(
            at: diagnosticsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var out: [PrivacyItem] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                // The archive of already-processed reports as ONE item.
                if entry.lastPathComponent == "Retired" {
                    add(&out, .diagnostics, .crashReports, entry)
                }
            } else if Self.diagnosticExtensions.contains(entry.pathExtension.lowercased()) {
                // Only genuine report files (.ips/.crash/.diag/.panic/…).
                add(&out, .diagnostics, .crashReports, entry)
            }
        }
        return out
    }

    // MARK: - Allowed locations

    /// Directory roots whose *contents* the Privacy cleaner may remove.
    /// Declarative — fixed paths derived from `libraryURL`, never from items.
    func roots() -> [URL] {
        [savedStateDir, diagnosticsDir]
    }

    /// Exact canonical locations the cleaner may remove *themselves*: the
    /// quarantine database (plus SQLite sidecars), the shell history files, the
    /// zsh sessions directory, and the QuickLook cache candidates. Declarative —
    /// the fixed list below, never derived from items.
    func exactTargets() -> [URL] {
        let quarantine = [quarantineDB] + ["-wal", "-shm", "-journal"].map {
            quarantineDB.deletingLastPathComponent()
                .appendingPathComponent(quarantineDB.lastPathComponent + $0)
        }
        let shell = Self.shellHistoryFileNames.map { homeURL.appendingPathComponent($0) }
        return quickLookCandidates + quarantine + shell + [zshSessionsDir]
    }

    // MARK: - Helpers

    /// Append a `PrivacyItem` if `url` exists, has non-zero size, and is not on
    /// the never-remove list — the same semantics as `PrivacyScanner`'s `add`.
    @discardableResult
    private func add(
        _ out: inout [PrivacyItem],
        _ app: PrivacyApp,
        _ kind: PrivacyItemKind,
        _ url: URL
    ) -> Bool {
        guard !PrivacyScanner.neverRemoveBasenames.contains(
            PrivacyScanner.normalizeBasename(url.lastPathComponent)
        ) else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = Scanner.allocatedSize(of: url)
        guard size > 0 else { return false }
        out.append(PrivacyItem(app: app, kind: kind, url: url, sizeBytes: size))
        return true
    }

    /// SQLite `-wal`/`-shm`/`-journal` sidecars are cleared together with their
    /// database — see `PrivacyScanner.addSidecars` for the rationale.
    private func addSidecars(
        _ out: inout [PrivacyItem],
        _ app: PrivacyApp,
        _ kind: PrivacyItemKind,
        of dbURL: URL
    ) {
        let dir = dbURL.deletingLastPathComponent()
        let base = dbURL.lastPathComponent
        for suffix in ["-wal", "-shm", "-journal"] {
            add(&out, app, kind, dir.appendingPathComponent(base + suffix))
        }
    }
}
