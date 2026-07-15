import Foundation

// MARK: - Model

/// One local copy of a mail attachment found under a Mail Downloads folder.
/// These are copies Mail writes to disk when an attachment is opened or saved;
/// the original stays with the message, so the copy is safe to remove.
public struct MailAttachment: Identifiable, Sendable, Hashable {
    public let url: URL
    public let sizeBytes: Int64
    public let modificationDate: Date?

    public var id: String { url.path }
    public var path: String { url.path }
    public var name: String { url.lastPathComponent }

    public init(url: URL, sizeBytes: Int64, modificationDate: Date?) {
        self.url = url
        self.sizeBytes = sizeBytes
        self.modificationDate = modificationDate
    }
}

/// Outcome of a Mail Downloads scan: everything found (largest first) plus
/// whether any root exists but could not be listed — on macOS the Mail
/// container is TCC-protected, so that means Full Disk Access is missing.
public struct MailAttachmentScanResult: Sendable {
    public let attachments: [MailAttachment]
    public let accessDenied: Bool

    public var totalBytes: Int64 { attachments.reduce(0) { $0 + $1.sizeBytes } }

    public init(attachments: [MailAttachment], accessDenied: Bool) {
        self.attachments = attachments
        self.accessDenied = accessDenied
    }
}

// MARK: - Scanner

/// Finds Apple Mail's local attachment copies and, on request, moves selected
/// ones to the Trash.
///
/// Safety notes:
///  * The scan roots are FIXED and declarative — the two folders where Mail
///    writes attachment copies, nothing else. The `SafetyPolicy` allowlist is
///    exactly these roots, never derived from the items being removed.
///  * Scanning is read-only and never follows symlinks, so a link planted in a
///    Mail Downloads folder can never pull outside files into the results.
///  * Removal goes through the shared `Cleaner`, which re-validates every path
///    against the policy and moves items to the Trash (recoverable).
public struct MailAttachmentScanner: Sendable {
    /// Directories whose contents may be scanned and cleaned. Injectable so
    /// tests can point at a sandbox; production uses `defaultRoots`.
    public let roots: [URL]
    public let policy: SafetyPolicy
    public let disposer: FileDisposer

    /// The two places Apple Mail stores local attachment copies: the sandboxed
    /// container (modern macOS) and the pre-sandbox legacy location.
    public static var defaultRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads"),
            home.appendingPathComponent("Library/Mail Downloads"),
        ]
    }

    public init(
        roots: [URL] = MailAttachmentScanner.defaultRoots,
        disposer: FileDisposer = TrashDisposer()
    ) {
        self.roots = roots
        self.policy = SafetyPolicy(allowedRoots: roots)
        self.disposer = disposer
    }

    // MARK: - Scanning (read-only)

    private static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
        .contentModificationDateKey,
    ]

    /// Recursively collect every regular file under the roots, largest first.
    /// A missing root is simply skipped; a root that exists but cannot be
    /// listed sets `accessDenied` (the UI hints at Full Disk Access).
    ///
    /// - Parameters:
    ///   - shouldContinue: polled per entry; returning `false` stops the walk
    ///     early and returns what was found so far.
    ///   - onFound: called for each attachment as it is discovered, on the
    ///     scanning thread — hop to the main actor before touching UI state.
    public func scan(
        shouldContinue: (() -> Bool)? = nil,
        onFound: ((MailAttachment) -> Void)? = nil
    ) -> MailAttachmentScanResult {
        let fm = FileManager.default
        var found: [MailAttachment] = []
        var accessDenied = false

        for root in roots.map(\.canonicalized) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
                continue   // root absent (e.g. no legacy folder) — nothing to do
            }

            // Probe readability up front: the Mail container exists for every
            // user but cannot be listed without Full Disk Access.
            guard (try? fm.contentsOfDirectory(atPath: root.path)) != nil else {
                accessDenied = true
                continue
            }

            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: Array(Self.resourceKeys),
                options: [.skipsHiddenFiles],   // never follows symlinks
                errorHandler: { _, _ in true }  // skip unreadable entries, keep going
            ) else { continue }

            for case let url as URL in enumerator {
                if shouldContinue?() == false {
                    found.sort { $0.sizeBytes > $1.sizeBytes }
                    return MailAttachmentScanResult(attachments: found, accessDenied: accessDenied)
                }

                guard let v = try? url.resourceValues(forKeys: Self.resourceKeys) else { continue }
                if v.isSymbolicLink == true { continue }
                guard v.isRegularFile == true else { continue }

                // SAFETY GATE: symlink-resolved containment inside the roots.
                guard policy.validate(url) == nil else { continue }

                let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0)
                let attachment = MailAttachment(
                    url: url,
                    sizeBytes: size,
                    modificationDate: v.contentModificationDate
                )
                found.append(attachment)
                onFound?(attachment)
            }
        }

        found.sort { $0.sizeBytes > $1.sizeBytes }
        return MailAttachmentScanResult(attachments: found, accessDenied: accessDenied)
    }

    // MARK: - Removal

    /// Move the given attachment copies to the Trash (or, in `dryRun`, report
    /// what *would* happen). Routed through the shared `Cleaner` so every path
    /// passes the audited safety gate again immediately before disposal.
    public func remove(_ attachments: [MailAttachment], dryRun: Bool) -> CleanReport {
        let items = attachments.map {
            ScanItem(url: $0.url, categoryID: "mail-attachments",
                     sizeBytes: $0.sizeBytes, modificationDate: $0.modificationDate)
        }
        return Cleaner(policy: policy, disposer: disposer).clean(items, dryRun: dryRun)
    }
}
