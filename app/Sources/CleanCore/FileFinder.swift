import Foundation

/// Finds large files in the user's *content* folders (Downloads, Documents,
/// Desktop, Movies, Music, Pictures) and, on request, moves selected ones to
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
public struct FileFinder {
    /// Folders to walk. Their contents (recursively) are candidates.
    public let roots: [URL]
    /// Gate that decides whether a discovered/selected file may be removed.
    public let policy: SafetyPolicy
    /// How a removal is carried out (Trash in production; recording in tests).
    public let disposer: FileDisposer

    public init(
        roots: [URL] = FileFinder.defaultRoots,
        policy: SafetyPolicy? = nil,
        disposer: FileDisposer = TrashDisposer()
    ) {
        self.roots = roots
        // The allowlist is precisely these roots: a file is only removable when
        // it lives strictly inside one of them.
        self.policy = policy ?? SafetyPolicy(allowedRoots: roots)
        self.disposer = disposer
    }

    /// The user-content folders scanned by default. Deliberately excludes
    /// `~/Library`, hidden dot-directories, and anything requiring root.
    public static var defaultRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Downloads", "Documents", "Desktop", "Movies", "Music", "Pictures"]
            .map { home.appendingPathComponent($0) }
    }

    // MARK: - Scanning (read-only)

    private static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey, .isAliasFileKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
        .contentModificationDateKey, .contentAccessDateKey, .contentTypeKey,
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
    ]

    /// Every regular file at least `minSizeBytes` big (optionally also older than
    /// `olderThanDays`), largest first. Never follows symlinks, never descends
    /// into packages, and skips iCloud placeholders. Returns at most `limit`.
    public func find(
        minSizeBytes: Int64,
        olderThanDays: Int? = nil,
        now: Date = Date(),
        limit: Int? = nil
    ) -> [LargeFile] {
        let fm = FileManager.default
        var found: [LargeFile] = []

        for root in roots {
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
                guard let file = candidate(url, minSizeBytes: minSizeBytes, olderThanDays: olderThanDays, now: now) else {
                    continue
                }
                found.append(file)
            }
        }

        found.sort { $0.sizeBytes > $1.sizeBytes }
        if let limit, found.count > limit { return Array(found.prefix(limit)) }
        return found
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

        let modDate = v.contentModificationDate
        if let olderThanDays, olderThanDays > 0 {
            guard let modDate, now.timeIntervalSince(modDate) / 86_400 >= Double(olderThanDays) else { return nil }
        }

        // SAFETY GATE: must live strictly inside an allowed root and pass every
        // other policy check (symlink-resolved, not protected, not too shallow).
        guard policy.validate(url) == nil else { return nil }

        return LargeFile(
            url: url,
            sizeBytes: size,
            modificationDate: modDate,
            accessDate: v.contentAccessDate,
            kind: FileKind.infer(contentType: v.contentType, url: url)
        )
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
