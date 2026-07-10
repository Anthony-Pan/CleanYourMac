import Foundation

/// Detects Chromium-embedded ("Electron") apps under `~/Library/Application
/// Support` by on-disk signature and offers a fixed set of disposable trace
/// entries inside each signature-verified profile ("tier") directory.
///
/// Safety and scope:
///
///  * Detection is strict, validated against real apps: a tier matches only
///    when it contains a Chromium *engine* artifact (`Code Cache`, `GPUCache`,
///    `Session Storage`) AND a Chromium *profile store* (`Local Storage`,
///    `IndexedDB`, a `Cookies` file, or a `Local State` file). A lone `Cache`
///    directory — common in native apps — is never sufficient.
///  * Only the fixed trace names below are ever offered. App content and
///    configuration siblings (`User/`, config JSON, databases) are structurally
///    out of reach — they are not in the table. History and Sessions are
///    deliberately NOT offered: for an unknown Chromium embedder those may hold
///    app data, not disposable traces.
///  * The known browser vendor directories belong to the dedicated browser
///    scanner and are skipped here, as is everything Apple (`com.apple.*`).
///  * `detectedRoots()` re-runs signature verification against the real disk —
///    the allowlist is never derived from the items being cleared.
struct ElectronTraceScanner {
    /// The `~/Library` base to search. Injectable so tests can point it at a
    /// sandbox instead of the real home.
    let libraryURL: URL

    // MARK: - Fixed trace tables

    /// Disposable engine caches — safe to clear for any Chromium embedder.
    private static let cacheNames = [
        "Cache", "Code Cache", "GPUCache", "DawnCache",
        "DawnGraphiteCache", "DawnWebGPUCache", "GrShaderCache", "ShaderCache",
        "GraphiteDawnCache", "blob_storage",
    ]

    /// Cookie database locations (modern `Network/Cookies` and legacy flat),
    /// cleared together with their SQLite sidecars.
    private static let cookieSubpaths = ["Cookies", "Network/Cookies"]

    /// Site data — opt-in via the shared `.siteData` kind (may sign the user out).
    private static let siteDataNames = [
        "Local Storage", "Session Storage", "IndexedDB",
        "Service Worker", "SharedStorage", "Shared Dictionary",
    ]

    /// Every basename this scanner can ever offer, lowercased and compared
    /// after the same sidecar normalisation as the denylist. `PrivacyScanner.clear`
    /// blocks any electron-attributed item whose basename is not in this set —
    /// structural defense in depth against crafted items pointing at app
    /// content inside a detected root.
    static let electronTraceBasenames: Set<String> = Set(
        (cacheNames + siteDataNames + ["Cookies"]).map { $0.lowercased() }
    )

    // MARK: - Detection

    /// Vendor directories that belong to the dedicated browser scanner and must
    /// never be re-offered here (their trace semantics differ — e.g. History is
    /// cleanable for a browser but off-limits for an unknown embedder).
    private static let knownBrowserDirNames: Set<String> = [
        "Google", "Microsoft Edge", "Microsoft Edge Beta", "Microsoft Edge Dev",
        "Microsoft Edge Canary", "BraveSoftware", "Vivaldi", "Arc", "Chromium",
        "Firefox", "com.operasoftware.Opera", "com.operasoftware.OperaGX",
        "com.apple.sharedfilelist",
    ]

    /// Known Application Support directory name → bundle identifier, used by
    /// the UI for the Running badge and the real app icon. Detection never
    /// depends on this table — unmapped apps simply carry no bundle id.
    static let knownBundleIDs: [String: String] = [
        "Slack": "com.tinyspeck.slackmacgap",
        "discord": "com.hnc.Discord",
        "Microsoft Teams": "com.microsoft.teams2",
        "Notion": "notion.id",
        "obsidian": "md.obsidian",
        "Figma": "com.figma.Desktop",
        "Signal": "org.whispersystems.signal-desktop",
        "Postman": "com.postmanlabs.mac",
        "Code": "com.microsoft.VSCode",
        "Code - Insiders": "com.microsoft.VSCodeInsiders",
        "Cursor": "com.todesktop.230313mzl4w4u92",
        "Claude": "com.anthropic.claudefordesktop",
        "UnityHub": "com.unity3d.unityhub",
        "WhatsApp": "net.whatsapp.WhatsApp",
    ]

    /// One signature-verified profile directory inside a matched app dir.
    private struct Tier {
        let url: URL
        /// Partition name for `Partitions/<p>` tiers; nil for top level and `Default`.
        let context: String?
    }

    private struct DetectedApp {
        let name: String
        let tiers: [Tier]
    }

    /// Enumerates `~/Library/Application Support` (one level, no hidden files)
    /// and returns every non-browser, non-Apple directory whose layout carries
    /// the strict Chromium signature, sorted by name for stable output.
    private func detectedApps() -> [DetectedApp] {
        let appSupport = libraryURL.appendingPathComponent("Application Support")
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: appSupport,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var out: [DetectedApp] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            guard !Self.knownBrowserDirNames.contains(name),
                  !name.hasPrefix("com.apple."),
                  isDirectory(entry) else { continue }
            let tiers = matchedTiers(in: entry)
            if !tiers.isEmpty {
                out.append(DetectedApp(name: name, tiers: tiers))
            }
        }
        return out
    }

    /// The candidate tiers of one app dir — top level, each `Partitions/<p>`,
    /// and `Default/` — filtered down to those matching the signature. The
    /// profile-store half may also be satisfied at the app dir's top level
    /// (Electron keeps `Local State` beside `Partitions/` and `Default/`).
    private func matchedTiers(in appDir: URL) -> [Tier] {
        var candidates: [Tier] = [Tier(url: appDir, context: nil)]

        let partitions = appDir.appendingPathComponent("Partitions")
        for partition in subdirectories(of: partitions) {
            candidates.append(Tier(url: partition, context: partition.lastPathComponent))
        }

        let defaultDir = appDir.appendingPathComponent("Default")
        if isDirectory(defaultDir) {
            candidates.append(Tier(url: defaultDir, context: nil))
        }

        // A symlinked `Default`/`Partitions/<p>` could resolve outside
        // Application Support; reject any tier whose canonical path escapes the
        // owning subtree so a symlink can never register a too-broad allowed root.
        let appSupport = libraryURL.appendingPathComponent("Application Support").canonicalized
        let topHasStore = hasProfileStore(in: appDir)
        return candidates.filter {
            hasEngineMarker(in: $0.url) && (hasProfileStore(in: $0.url) || topHasStore)
                && appSupport.isStrictAncestor(of: $0.url.canonicalized)
        }
    }

    /// Signature half 1: a Chromium engine artifact is present in `dir`.
    private func hasEngineMarker(in dir: URL) -> Bool {
        ["Code Cache", "GPUCache", "Session Storage"].contains {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
    }

    /// Signature half 2: a Chromium profile store is present in `dir`. `Cookies`
    /// and `Local State` must be regular files — a *directory* with either name
    /// is not Chromium and must not count.
    private func hasProfileStore(in dir: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.appendingPathComponent("Local Storage").path) { return true }
        if fm.fileExists(atPath: dir.appendingPathComponent("IndexedDB").path) { return true }
        return isRegularFile(dir.appendingPathComponent("Cookies"))
            || isRegularFile(dir.appendingPathComponent("Local State"))
    }

    // MARK: - Scanning (read-only)

    /// One `PrivacyGroup` per detected app, offering only the fixed trace
    /// entries from each matched tier. Apps whose tiers hold no non-empty
    /// traces produce no group.
    func groups() -> [PrivacyGroup] {
        detectedApps().compactMap { detected in
            let app = PrivacyApp.electron(
                name: detected.name,
                bundleID: Self.knownBundleIDs[detected.name]
            )
            var items: [PrivacyItem] = []
            for tier in detected.tiers {
                collectTraces(&items, app: app, tier: tier)
            }
            return items.isEmpty ? nil : PrivacyGroup(app: app, items: items)
        }
    }

    /// Appends every existing, non-empty fixed trace entry found in one tier.
    private func collectTraces(_ out: inout [PrivacyItem], app: PrivacyApp, tier: Tier) {
        for name in Self.cacheNames {
            add(&out, app, .caches, tier.url.appendingPathComponent(name), context: tier.context)
        }

        for subpath in Self.cookieSubpaths {
            let cookies = tier.url.appendingPathComponent(subpath)
            if add(&out, app, .cookies, cookies, context: tier.context) {
                addSidecars(&out, app, .cookies, of: cookies, context: tier.context)
            }
        }

        for name in Self.siteDataNames {
            add(&out, app, .siteData, tier.url.appendingPathComponent(name), context: tier.context)
        }
    }

    // MARK: - Allowed roots

    /// The parent directories of every offer-able trace: each signature-matched
    /// tier directory plus its `Network` subdirectory (the modern cookies
    /// parent). Re-read from the real disk layout on every call — never derived
    /// from the items being cleared — following the same sanctioned precedent
    /// as Chromium/Firefox profile enumeration.
    func detectedRoots() -> [URL] {
        detectedApps().flatMap { detected in
            detected.tiers.flatMap {
                [$0.url, $0.url.appendingPathComponent("Network")]
            }
        }
    }

    // MARK: - Helpers

    /// Append a `PrivacyItem` if `url` exists, has non-zero size, and is not on
    /// the never-remove list — the same semantics as `PrivacyScanner`'s `add`.
    @discardableResult
    private func add(
        _ out: inout [PrivacyItem],
        _ app: PrivacyApp,
        _ kind: PrivacyItemKind,
        _ url: URL,
        context: String? = nil
    ) -> Bool {
        guard !PrivacyScanner.neverRemoveBasenames.contains(
            PrivacyScanner.normalizeBasename(url.lastPathComponent)
        ) else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = Scanner.allocatedSize(of: url)
        guard size > 0 else { return false }
        out.append(PrivacyItem(app: app, kind: kind, url: url, sizeBytes: size, context: context))
        return true
    }

    /// SQLite `-wal`/`-shm`/`-journal` sidecars are cleared together with their
    /// database — see `PrivacyScanner.addSidecars` for the rationale.
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

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func isRegularFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
    }

    private func subdirectories(of url: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries.filter { isDirectory($0) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
