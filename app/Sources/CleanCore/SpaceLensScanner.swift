import Foundation

// MARK: - Entry

/// One immediate child of an explored folder, sized recursively. Space Lens is
/// strictly read-only: entries are only listed and displayed, never deleted.
public struct SpaceLensEntry: Identifiable, Sendable, Hashable {
    public let url: URL
    public let name: String
    public let sizeBytes: Int64
    public let isDirectory: Bool
    /// True for bundle packages (.app, .photoslibrary, .framework, …). Sized in
    /// full like any directory, but presented as a leaf the UI never drills into.
    public let isPackage: Bool
    /// Recursive regular-file count for directories; nil for plain files.
    public let itemCount: Int?

    public var id: String { url.path }
    public var path: String { url.path }

    public init(
        url: URL,
        name: String,
        sizeBytes: Int64,
        isDirectory: Bool,
        isPackage: Bool = false,
        itemCount: Int? = nil
    ) {
        self.url = url
        self.name = name
        self.sizeBytes = sizeBytes
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.itemCount = itemCount
    }
}

// MARK: - Scanner

/// Sizes the immediate children of one folder, with recursive totals for
/// directories. Read-only by construction: it never modifies the filesystem,
/// never follows symlinks, and treats bundle packages as opaque leaves.
public struct SpaceLensScanner: Sendable {
    public init() {}

    /// Progress reported while a folder scan runs.
    public enum Event: Sendable {
        /// Started sizing this child (its display name).
        case sizing(String)
        /// A child was fully sized.
        case entry(SpaceLensEntry)
        /// The folder itself could not be listed (permission denied, missing).
        case rootUnreadable
    }

    /// Cancellation is polled this often while walking a directory's contents.
    private static let cancelCheckInterval = 64

    private static let childKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
    ]

    private static let sizeKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
    ]

    /// All immediate children of `root`, sized, largest first.
    public func scan(root: URL) -> [SpaceLensEntry] {
        var entries: [SpaceLensEntry] = []
        scanIncremental(root: root) { event in
            if case .entry(let entry) = event { entries.append(entry) }
        }
        return entries.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Size each immediate child of `root`, reporting progress as it goes.
    /// `onEvent` is called synchronously on the calling thread. `Task.isCancelled`
    /// is checked between children (and periodically inside big directory walks)
    /// so a cancelled task stops early with whatever was already reported.
    public func scanIncremental(root: URL, onEvent: (Event) -> Void) {
        let fm = FileManager.default
        // Hidden children are real space: list them too (no .skipsHiddenFiles).
        guard let children = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: Array(Self.childKeys), options: []
        ) else {
            onEvent(.rootUnreadable)
            return
        }

        for child in children {
            if Task.isCancelled { return }
            onEvent(.sizing(child.lastPathComponent))
            guard let entry = makeEntry(for: child) else { continue }
            // Sizing may have been interrupted mid-walk; never publish a
            // partial total as if it were complete.
            if Task.isCancelled { return }
            onEvent(.entry(entry))
        }
    }

    /// Bundle-package detection: LaunchServices metadata when available, plus a
    /// fixed fallback list of well-known bundle extensions so a `.app` directory
    /// is treated as a package even where the metadata is missing (bare test
    /// sandboxes, foreign volumes).
    public static func isPackage(_ url: URL) -> Bool {
        if (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true { return true }
        return knownPackageExtensions.contains(url.pathExtension.lowercased())
    }

    private static let knownPackageExtensions: Set<String> = [
        "app", "framework", "bundle", "plugin", "appex", "kext", "xcodeproj",
        "xcworkspace", "playground", "photoslibrary", "musiclibrary", "tvlibrary",
        "imovielibrary", "fcpbundle", "logicx", "band", "docset",
    ]

    // MARK: - Sizing

    private func makeEntry(for child: URL) -> SpaceLensEntry? {
        // Unreadable child (permission denied, vanished mid-scan): skip it and
        // keep scanning — one bad child must never abort the whole folder.
        guard let values = try? child.resourceValues(forKeys: Self.childKeys) else { return nil }
        let name = child.lastPathComponent

        // Never traverse or resolve symlinks: the link itself is ~0 bytes and
        // its target may live anywhere (resource values describe the link, not
        // the destination).
        if values.isSymbolicLink == true {
            return SpaceLensEntry(url: child, name: name, sizeBytes: 0, isDirectory: false)
        }

        if values.isDirectory == true {
            let totals = directoryTotals(of: child)
            return SpaceLensEntry(
                url: child, name: name, sizeBytes: totals.bytes,
                isDirectory: true, isPackage: Self.isPackage(child), itemCount: totals.files)
        }

        return SpaceLensEntry(url: child, name: name, sizeBytes: Self.fileSize(values), isDirectory: false)
    }

    /// Recursive allocated bytes + regular-file count. Mirrors
    /// `Scanner.allocatedSize`: only regular files count toward the total,
    /// symlinks are never followed (default enumeration does not traverse
    /// them), and hidden files are included.
    private func directoryTotals(of dir: URL) -> (bytes: Int64, files: Int) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: Array(Self.sizeKeys),
            options: [],                       // include hidden; never follows symlinks
            errorHandler: { _, _ in true }     // skip unreadable entries, keep going
        ) else { return (0, 0) }

        var bytes: Int64 = 0
        var files = 0
        var visited = 0
        for case let item as URL in enumerator {
            visited += 1
            if visited % Self.cancelCheckInterval == 0, Task.isCancelled { break }
            guard let v = try? item.resourceValues(forKeys: Self.sizeKeys),
                  v.isRegularFile == true else { continue }
            bytes += Self.fileSize(v)
            files += 1
        }
        return (bytes, files)
    }

    /// Allocated size with logical fallback — the same chain `Scanner` uses.
    private static func fileSize(_ v: URLResourceValues) -> Int64 {
        Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0)
    }
}
