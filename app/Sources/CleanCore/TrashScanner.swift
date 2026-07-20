import Foundation

// MARK: - Model

/// One top-level thing the user threw away — a file or folder sitting in a
/// Trash bin. A discarded folder is a single row; its contents were discarded
/// together and are removed together.
public struct TrashItem: Identifiable, Sendable, Hashable {
    public let url: URL
    public let sizeBytes: Int64
    public let modificationDate: Date?
    public let isDirectory: Bool
    /// The bin this item was found in (`TrashBin.id`). A grouping tag for the
    /// UI only — deletion safety never consults it, so a forged tag cannot
    /// widen what the remover accepts.
    public let binID: String

    public var id: String { url.path }
    public var path: String { url.path }
    public var name: String { url.lastPathComponent }

    public init(url: URL, sizeBytes: Int64, modificationDate: Date?,
                isDirectory: Bool, binID: String = "") {
        self.url = url
        self.sizeBytes = sizeBytes
        self.modificationDate = modificationDate
        self.isDirectory = isDirectory
        self.binID = binID
    }
}

public extension Array where Element == TrashItem {
    /// Sum of every item's size — what emptying all of it would free.
    var totalBytes: Int64 { reduce(0) { $0 + $1.sizeBytes } }
}

// MARK: - Bin

/// One Trash location produced by `TrashBinDiscovery`. Bins exist only
/// because the discovery rule says so — nothing found while scanning can
/// introduce one.
public struct TrashBin: Identifiable, Sendable, Hashable {
    public let root: URL
    /// What the UI calls this bin: the volume's name, or a fixed label for
    /// the user's Trash on the boot volume.
    public let displayName: String
    public let isUserTrash: Bool
    /// False when the bin's directory exists but its contents cannot be
    /// listed (typically missing Full Disk Access). An inaccessible bin is
    /// surfaced to the user, never silently dropped, so "Trash is empty"
    /// can never mean "Trash could not be read".
    public let isAccessible: Bool

    public var id: String { root.path }

    public init(root: URL, displayName: String, isUserTrash: Bool, isAccessible: Bool) {
        self.root = root
        self.displayName = displayName
        self.isUserTrash = isUserTrash
        self.isAccessible = isAccessible
    }
}

// MARK: - Discovery

/// Finds every Trash bin this module may read and empty, by fixed rule:
/// the user's Trash, plus `<volume>/.Trashes/<uid>` on every mounted
/// non-boot, non-hidden volume. The rule alone decides the deletable roots —
/// they are never derived from anything a scan finds, so scanned content can
/// never widen where deletion is allowed.
///
/// The volume list is injectable so tests can present temp directories as
/// volumes; the per-volume path rule itself is not configurable.
public struct TrashBinDiscovery: Sendable {
    /// A mounted volume as discovery sees it.
    public struct Volume: Sendable, Hashable {
        public let url: URL
        public let name: String

        public init(url: URL, name: String) {
            self.url = url
            self.name = name
        }
    }

    /// Fixed declarative root of the user's own Trash, always the first bin.
    public let userTrashRoot: URL
    private let volumeProvider: @Sendable () -> [Volume]

    public init(
        userTrashRoot: URL = TrashScanner.defaultTrashRoot(),
        volumeProvider: @escaping @Sendable () -> [Volume] = TrashBinDiscovery.mountedNonBootVolumes
    ) {
        self.userTrashRoot = userTrashRoot
        self.volumeProvider = volumeProvider
    }

    /// Mounted, non-hidden volumes excluding the boot volume "/" — the boot
    /// volume's trash is the user's Trash, which is covered separately.
    public static func mountedNonBootVolumes() -> [Volume] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey],
            options: [.skipHiddenVolumes]
        ) ?? []
        return urls.compactMap { url in
            guard url.path != "/" else { return nil }
            let name = (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
                ?? url.lastPathComponent
            return Volume(url: url, name: name)
        }
    }

    /// The user's bin first, then one bin per volume that has a
    /// `.Trashes/<uid>` directory. A volume without that directory simply has
    /// no bin; a bin whose directory cannot be listed is included as
    /// inaccessible rather than dropped.
    public func discoverBins() -> [TrashBin] {
        var bins = [TrashBin(
            root: userTrashRoot,
            displayName: "User Trash",
            isUserTrash: true,
            isAccessible: isListable(userTrashRoot)
        )]
        for volume in volumeProvider() {
            // The fixed per-volume rule: <volume>/.Trashes/<uid>. Nothing
            // else on the volume is ever considered.
            let root = volume.url
                .appendingPathComponent(".Trashes", isDirectory: true)
                .appendingPathComponent(String(getuid()), isDirectory: true)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            bins.append(TrashBin(
                root: root,
                displayName: volume.name,
                isUserTrash: false,
                isAccessible: isListable(root)
            ))
        }
        return bins
    }

    /// A directory that exists but cannot be listed is inaccessible. A
    /// missing directory counts as listable: scanning it honestly yields
    /// zero items, which is different from "could not look".
    private func isListable(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return true
        }
        return (try? fm.contentsOfDirectory(atPath: url.path)) != nil
    }
}

// MARK: - Scanner

/// Lists what is sitting in one Trash bin. Read-only — `TrashScanner`
/// never modifies the filesystem.
///
/// Scope: one bin per scanner. `scanBins` walks the full set produced by
/// `TrashBinDiscovery` — the user's Trash plus per-volume bins.
public struct TrashScanner: Sendable {
    /// Fixed declarative root, resolved once at init. Injectable for tests.
    public let trashRoot: URL

    public init(trashRoot: URL = TrashScanner.defaultTrashRoot()) {
        self.trashRoot = trashRoot
    }

    /// The user's Trash as reported by the system, falling back to `~/.Trash`.
    public static func defaultTrashRoot() -> URL {
        FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }

    /// Top-level items of the bin, largest first. Directory sizes are
    /// recursive (allocated bytes, mirroring `Scanner`; symlinks are never
    /// followed). Items that fail to stat are skipped rather than crashing.
    /// `onItem` fires synchronously as each item is sized, for live progress.
    public func scan(onItem: ((TrashItem) -> Void)? = nil) -> [TrashItem] {
        let fm = FileManager.default
        let children = (try? fm.contentsOfDirectory(
            at: trashRoot, includingPropertiesForKeys: nil, options: []
        )) ?? []

        var items: [TrashItem] = []
        for child in children {
            // Finder's bookkeeping file, not something the user threw away.
            if child.lastPathComponent == ".DS_Store" { continue }

            // lstat semantics: never traverses a final symlink, so a link is
            // described (and, if allowed, removed) as the link itself.
            guard let attrs = try? fm.attributesOfItem(atPath: child.path),
                  let type = attrs[.type] as? FileAttributeType else { continue }

            let isDirectory = type == .typeDirectory
            let size: Int64
            if type == .typeSymbolicLink {
                size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            } else {
                size = Scanner.allocatedSize(of: child)
            }

            let item = TrashItem(
                url: child,
                sizeBytes: size,
                modificationDate: attrs[.modificationDate] as? Date,
                isDirectory: isDirectory,
                binID: trashRoot.path
            )
            items.append(item)
            onItem?(item)
        }
        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Walks every accessible bin in order, streaming each item as it is
    /// sized and tagging it with its bin for grouping. Inaccessible bins are
    /// skipped here — listing them would fail anyway — and it is the
    /// caller's job to surface them, never to present their absence as
    /// "empty". Returns one flat list, largest first.
    public static func scanBins(_ bins: [TrashBin],
                                onItem: ((TrashItem) -> Void)? = nil) -> [TrashItem] {
        var all: [TrashItem] = []
        for bin in bins where bin.isAccessible {
            if Task.isCancelled { break }
            all.append(contentsOf: TrashScanner(trashRoot: bin.root).scan(onItem: onItem))
        }
        return all.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}

// MARK: - Report

/// Outcome of one permanent-removal pass — mirrors `CleanReport`, except the
/// items are *removed*, not trashed: there is no undo.
public struct TrashRemovalReport: Sendable {
    public var removed: [String] = []
    public var blocked: [SafetyRejection] = []
    public var failed: [CleanFailure] = []
    public var freedBytes: Int64 = 0

    public init() {}
}

// MARK: - Remover

/// Permanently deletes items out of Trash bins. This is the one place in the
/// app where deletion is genuinely permanent — the items were already deleted
/// once when the user threw them away, so there is no Trash to move them to.
///
/// Every URL must pass a `SafetyPolicy` whose allowed roots are exactly the
/// bin roots produced by `TrashBinDiscovery`'s fixed rule (declarative —
/// never derived from the items being deleted). The policy resolves
/// symlinks, so a link that points outside every bin is refused rather than
/// followed, and each bin root itself is always refused.
public struct TrashRemover: Sendable {
    public let binRoots: [URL]
    public let policy: SafetyPolicy

    public init(binRoots: [URL]) {
        self.binRoots = binRoots
        self.policy = SafetyPolicy(allowedRoots: binRoots)
    }

    /// Single-bin convenience: the user's Trash alone.
    public init(trashRoot: URL = TrashScanner.defaultTrashRoot()) {
        self.init(binRoots: [trashRoot])
    }

    public func remove(_ items: [TrashItem]) -> TrashRemovalReport {
        var report = TrashRemovalReport()
        let fm = FileManager.default

        for item in items {
            // SAFETY GATE: refuse anything outside every bin, each bin root
            // itself, or a symlink that resolves elsewhere.
            if let rejection = policy.validate(item.url) {
                report.blocked.append(rejection)
                continue
            }

            do {
                try fm.removeItem(at: item.url)
                report.removed.append(item.path)
                report.freedBytes += item.sizeBytes
            } catch {
                report.failed.append(CleanFailure(path: item.path, error: String(describing: error)))
            }
        }
        return report
    }
}
