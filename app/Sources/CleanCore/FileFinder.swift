import Foundation

/// Finds large files in the user's *content* folders (Downloads, Documents,
/// Desktop, Movies, Music, Pictures — plus any folders the user explicitly
/// added, see `ScanLocationPolicy`) and, on request, moves selected ones to
/// the Trash.
///
/// Safety notes — this feature touches the user's own documents, so it is the
/// most conservative surface in the app:
///
///  * Scanning is read-only. Nothing is removed until `remove(_:dryRun:)` is
///    called with `dryRun: false`, and even then every path is re-validated by
///    the shared `Cleaner`/`SafetyPolicy` gate immediately before disposal.
///  * The `SafetyPolicy` allowlist is exactly the scan roots, so a file can
///    only ever be trashed if it lives strictly inside one of them. The system,
///    `~/Library` and the home folder itself are never touched.
///  * Symlinks, aliases, packages (`.app`, `.photoslibrary`, …) and iCloud /
///    dataless placeholder files are skipped — we never offer to remove a
///    proxy for something that lives elsewhere.
///  * `excludedDirs` (default: `~/Library`, `~/.Trash`) are never walked, even
///    when a scan root contains them.
public struct FileFinder {
    /// Folders to walk. Their contents (recursively) are candidates.
    public let roots: [URL]
    /// Gate that decides whether a discovered/selected file may be removed.
    public let policy: SafetyPolicy
    /// How a removal is carried out (Trash in production; recording in tests).
    public let disposer: FileDisposer
    /// Directories the walk never descends into, even inside a scan root.
    /// Belt-and-braces: `.skipsHiddenFiles` already skips `~/Library` (hidden
    /// flag) and dot-directories, but if a user adds a custom root above them —
    /// or the hidden flag is absent — we must still never walk them.
    public let excludedDirs: [URL]

    public init(
        roots: [URL] = FileFinder.defaultRoots,
        policy: SafetyPolicy? = nil,
        disposer: FileDisposer = TrashDisposer(),
        excludedDirs: [URL] = FileFinder.defaultExcludedDirs
    ) {
        self.roots = roots
        // The allowlist is precisely these roots: a file is only removable when
        // it lives strictly inside one of them.
        self.policy = policy ?? SafetyPolicy(allowedRoots: roots)
        self.disposer = disposer
        self.excludedDirs = excludedDirs.map { $0.canonicalized }
    }

    /// The user-content folders scanned by default. Deliberately excludes
    /// `~/Library`, hidden dot-directories, and anything requiring root.
    public static var defaultRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Downloads", "Documents", "Desktop", "Movies", "Music", "Pictures"]
            .map { home.appendingPathComponent($0) }
    }

    /// Never walked regardless of the chosen roots: the user's `~/Library`
    /// (caches/settings belong to Smart Scan, documents don't live there) and
    /// the Trash (its contents are already scheduled for deletion).
    public static var defaultExcludedDirs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library"),
            home.appendingPathComponent(".Trash"),
        ]
    }

    // MARK: - Scanning (read-only)

    private static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isAliasFileKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
        .contentModificationDateKey, .contentAccessDateKey, .contentTypeKey,
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
    ]

    /// How often (in enumerated entries) the cancellation hook is polled.
    private static let cancelCheckInterval = 256
    /// How often (in enumerated entries) the progress hook is invoked.
    private static let progressInterval = 512

    /// Every regular file at least `minSizeBytes` big (optionally also unused
    /// for at least `olderThanDays` days — judged by `LargeFile.lastUsedDate`,
    /// the later of modified/opened), largest first. Never follows symlinks,
    /// never descends into packages or `excludedDirs`, and skips iCloud
    /// placeholders. Returns at most `limit`.
    ///
    /// - Parameters:
    ///   - shouldContinue: polled every ~256 entries; returning `false` stops
    ///     the walk early and returns everything found so far (still sorted).
    ///     Lets a UI Stop button land on partial results instead of nothing.
    ///   - onProgress: called every ~512 entries with (entries examined,
    ///     candidates found so far). Called on the scanning thread — hop to the
    ///     main actor before touching UI state.
    public func find(
        minSizeBytes: Int64,
        olderThanDays: Int? = nil,
        now: Date = Date(),
        limit: Int? = nil,
        shouldContinue: (() -> Bool)? = nil,
        onProgress: ((_ scannedCount: Int, _ foundCount: Int) -> Void)? = nil
    ) -> [LargeFile] {
        let fm = FileManager.default
        var found: [LargeFile] = []
        var scanned = 0
        var stopped = false

        for rawRoot in roots {
            guard !stopped else { break }
            // Walk from the canonical root so every yielded path is symlink-free
            // and comparable against the (also canonical) excluded dirs.
            let root = rawRoot.canonicalized
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { continue }

            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: Array(Self.resourceKeys),
                // Do not descend into hidden trees (dot-dirs / VCS internals) or
                // into packages — a package is opaque, not a folder of files.
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }   // skip unreadable entries, keep going
            ) else { continue }

            for case let url as URL in enumerator {
                scanned += 1
                if scanned % Self.cancelCheckInterval == 0, shouldContinue?() == false {
                    stopped = true
                    break
                }
                if scanned % Self.progressInterval == 0 {
                    onProgress?(scanned, found.count)
                }

                // Never walk into an excluded directory (e.g. ~/Library inside
                // a custom root above home).
                if isExcluded(url) {
                    enumerator.skipDescendants()
                    continue
                }

                guard let file = candidate(url, minSizeBytes: minSizeBytes, olderThanDays: olderThanDays, now: now) else {
                    continue
                }
                found.append(file)
            }
        }

        onProgress?(scanned, found.count)
        found.sort { $0.sizeBytes > $1.sizeBytes }
        if let limit, found.count > limit { return Array(found.prefix(limit)) }
        return found
    }

    /// True when `url` is one of the excluded directories or lives inside one.
    /// Compared on standardized paths (excluded dirs are canonicalized at init;
    /// enumerated URLs come from the real walk, so they contain no links we'd
    /// follow).
    private func isExcluded(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return excludedDirs.contains { path == $0.path || path.hasPrefix($0.path + "/") }
    }

    /// Evaluate one enumerated URL. Returns a `LargeFile` when it is a real,
    /// local, on-disk regular file that passes the size/age filters and the
    /// safety gate; otherwise `nil`.
    private func candidate(_ url: URL, minSizeBytes: Int64, olderThanDays: Int?, now: Date) -> LargeFile? {
        guard let v = try? url.resourceValues(forKeys: Self.resourceKeys) else { return nil }

        // Only genuine, local regular files. Reject directories, symlinks,
        // aliases, packages and anything that is a proxy for data elsewhere.
        guard v.isRegularFile == true else { return nil }
        if v.isSymbolicLink == true || v.isAliasFile == true || v.isPackage == true { return nil }

        // iCloud / dataless placeholders: never offer to remove a file whose
        // bytes live in the cloud (removing it deletes it everywhere).
        if v.isUbiquitousItem == true { return nil }
        if let status = v.ubiquitousItemDownloadingStatus, status != .current { return nil }

        let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0)
        guard size >= minSizeBytes else { return nil }

        // SAFETY GATE: must live strictly inside an allowed root and pass every
        // other policy check (symlink-resolved, not protected, not too shallow).
        guard policy.validate(url) == nil else { return nil }

        let file = LargeFile(
            url: url,
            sizeBytes: size,
            modificationDate: v.contentModificationDate,
            accessDate: v.contentAccessDate,
            kind: FileKind.infer(contentType: v.contentType, url: url)
        )

        // Age filter shares `LargeFile.isOlder` so engine and UI agree on what
        // "old" means: unused (neither modified nor opened) for the given span.
        // Files with no known dates never qualify as old.
        if let olderThanDays, olderThanDays > 0 {
            guard file.isOlder(thanDays: olderThanDays, now: now) else { return nil }
        }

        return file
    }

    // MARK: - Removal

    /// Move the given files to the Trash (or, in `dryRun`, report what *would*
    /// happen). Routed through the shared `Cleaner` so removal goes through the
    /// exact same audited safety gate as every other cleanup in the app.
    public func remove(_ files: [LargeFile], dryRun: Bool) -> CleanReport {
        let items = files.map {
            ScanItem(url: $0.url, categoryID: "large-files", sizeBytes: $0.sizeBytes, modificationDate: $0.modificationDate)
        }
        return Cleaner(policy: policy, disposer: disposer).clean(items, dryRun: dryRun)
    }
}
