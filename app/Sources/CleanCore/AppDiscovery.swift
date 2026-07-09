import Foundation

/// Read-only discovery of installed applications. Never modifies the filesystem.
/// Reads each bundle's `Contents/Info.plist` (binary or XML) to recover the
/// identity we later use to attribute leftover files.
public struct AppDiscovery {
    public let policy: UninstallPolicy

    public init(policy: UninstallPolicy = UninstallPolicy()) {
        self.policy = policy
    }

    /// Every `.app` found in the configured app roots that the policy would
    /// allow us to remove, sorted largest-first. Apple/system apps are included
    /// but flagged `isSystem` (the UI must refuse them).
    public func installedApps() -> [InstalledApp] {
        appBundleURLs()
            .compactMap { readApp(at: $0, sized: true) }
            .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Phase 1 — metadata only: directory listing plus Info.plist reads, with
    /// NO size walk, so it returns in well under a second even with hundreds
    /// of apps. `sizeBytes` is `0` as a not-yet-sized sentinel; callers must
    /// treat it as "pending" and never render it — real sizes arrive through
    /// `sizeStream(for:)`. Sorted by name so the list order is stable while
    /// sizes stream in.
    public func discoverAppsFast() -> [InstalledApp] {
        appBundleURLs()
            .compactMap { readApp(at: $0, sized: false) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Phase 2 — stream real bundle sizes for `apps` in the given order.
    /// Concurrency is bounded so one huge bundle (an Xcode walk) can't starve
    /// the pool. Yields `(id, bytes)` as each walk finishes; when the consumer
    /// terminates the stream, no new walks are dispatched.
    public func sizeStream(for apps: [InstalledApp]) -> AsyncStream<(id: String, bytes: Int64)> {
        AsyncStream { continuation in
            let producer = Task.detached(priority: .utility) {
                // TODO(perf): thread shouldContinue into Scanner.allocatedSize
                // so an in-flight walk can stop early too; today cancellation
                // only stops new walks (at most `width` in flight finish late
                // and their results are discarded by the closed stream).
                await withTaskGroup(of: (String, Int64).self) { group in
                    let width = min(4, ProcessInfo.processInfo.activeProcessorCount)
                    var pending = apps.makeIterator()

                    func walkNext() -> Bool {
                        guard let app = pending.next() else { return false }
                        group.addTask { (app.id, Scanner.allocatedSize(of: app.url)) }
                        return true
                    }

                    var inFlight = 0
                    while inFlight < width, walkNext() { inFlight += 1 }
                    while let result = await group.next() {
                        continuation.yield(result)
                        if !Task.isCancelled { _ = walkNext() }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    /// The deduplicated, safety-gated `.app` bundles across all configured
    /// roots — the shared listing behind both discovery passes.
    private func appBundleURLs() -> [URL] {
        let fm = FileManager.default
        var seen = Set<String>()
        var bundles: [URL] = []

        for root in policy.appRoots {
            let children = (try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            for child in children where child.pathExtension == "app" {
                // Skip duplicates reachable via more than one root / symlink.
                guard seen.insert(child.canonicalized.path).inserted else { continue }
                // SAFETY GATE: only surface bundles we could actually remove.
                guard policy.validateBundle(child) == nil else { continue }
                bundles.append(child)
            }
        }

        return bundles
    }

    /// Parse a single `.app` bundle into an `InstalledApp`. Returns `nil` if the
    /// path is not a real application bundle directory.
    public func readApp(at url: URL) -> InstalledApp? {
        readApp(at: url, sized: true)
    }

    /// `sized: false` skips the recursive size walk (fast metadata pass) and
    /// leaves `sizeBytes` at the 0 pending sentinel.
    private func readApp(at url: URL, sized: Bool) -> InstalledApp? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }

        let info = Self.infoDictionary(at: url)
        let bundleID = (info?["CFBundleIdentifier"] as? String)?.cleaned
        let displayName = (info?["CFBundleDisplayName"] as? String)?.cleaned
        let bundleName = (info?["CFBundleName"] as? String)?.cleaned
        let version = (info?["CFBundleShortVersionString"] as? String)?.cleaned
        // Use the bundle's file name (what Finder shows in /Applications) as the
        // display name, so apps that share a CFBundleDisplayName — e.g. "Xcode"
        // and "Xcode-beta", both CFBundleName "Xcode" — stay distinguishable.
        let fileName = url.deletingPathExtension().lastPathComponent
        let name = fileName.isEmpty ? (displayName ?? bundleName ?? "Unknown") : fileName

        return InstalledApp(
            url: url,
            name: name,
            bundleID: bundleID,
            version: version,
            sizeBytes: sized ? Scanner.allocatedSize(of: url) : 0,
            isSystem: Self.isSystemApp(bundleID: bundleID, url: url)
        )
    }

    // MARK: - Helpers

    /// Read `Contents/Info.plist`. `PropertyListSerialization` transparently
    /// handles both binary and XML property lists.
    static func infoDictionary(at appURL: URL) -> [String: Any]? {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        else { return nil }
        return obj as? [String: Any]
    }

    /// Bundle identifiers of the extensions / helpers embedded *inside* an app
    /// bundle (app extensions, XPC services, bundled login-item apps). Used to
    /// tell a genuine `com.foo.Bar.ShareExtension` leftover apart from an
    /// independently-installed app that merely shares the id namespace
    /// (e.g. `com.google.Chrome` vs `com.google.Chrome.canary`).
    static func embeddedBundleIDs(of appURL: URL) -> Set<String> {
        let fm = FileManager.default
        let containers = [
            "Contents/PlugIns",
            "Contents/Extensions",
            "Contents/XPCServices",
            "Contents/Library/LoginItems",
            "Contents/Library/LaunchServices",
        ]
        var ids = Set<String>()
        for container in containers {
            let dir = appURL.appendingPathComponent(container)
            let children = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])) ?? []
            for child in children {
                // Each child is itself a bundle (.appex/.xpc/.app) with an Info.plist.
                if let id = (infoDictionary(at: child)?["CFBundleIdentifier"] as? String)?.cleaned?.lowercased() {
                    ids.insert(id)
                }
            }
        }
        return ids
    }

    /// An app is an untouchable *system* app only when it physically lives under
    /// `/System` (SIP-protected; we don't even scan there, but a symlink could
    /// point in). Apple apps installed in `/Applications` — Xcode, Xcode-beta,
    /// Configurator, the pro apps — are user-removable and must NOT be blocked
    /// just for carrying a `com.apple.*` identifier.
    static func isSystemApp(bundleID: String?, url: URL) -> Bool {
        let system = URL(fileURLWithPath: "/System").canonicalized
        return system.isSameOrAncestor(of: url.canonicalized)
    }
}

private extension String {
    /// Trimmed, or `nil` when empty after trimming.
    var cleaned: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
