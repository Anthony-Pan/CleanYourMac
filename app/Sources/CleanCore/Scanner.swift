import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Walks the declared cleanup targets and reports what can be reclaimed.
/// Read-only: `Scanner` never modifies the filesystem.
public struct Scanner {
    public let policy: SafetyPolicy

    public init(policy: SafetyPolicy) {
        self.policy = policy
    }

    public func scan(categories: [CleanupCategory], now: Date = Date()) -> [ScanResultGroup] {
        categories.map { scan(category: $0, now: now) }
    }

    public func scan(category: CleanupCategory, now: Date = Date()) -> ScanResultGroup {
        var result = ScanResultGroup(category: category, items: [])
        scanIncremental(categories: [category], now: now) { event in
            if case .categoryDone(let group) = event { result = group }
        }
        return result
    }

    /// Progress reported while an incremental scan runs.
    public enum ScanEvent: Sendable {
        /// Started scanning this category (its display name).
        case location(String)
        /// A reclaimable item was found and sized.
        case item(ScanItem)
        /// A category finished; its items (largest first).
        case categoryDone(ScanResultGroup)
    }

    /// Scan each category, reporting progress as it goes so the UI can show the
    /// discovery happening item by item instead of blocking on a spinner.
    /// `onEvent` is called synchronously on the calling thread.
    public func scanIncremental(
        categories: [CleanupCategory],
        now: Date = Date(),
        onEvent: (ScanEvent) -> Void
    ) {
        let fm = FileManager.default

        for category in categories {
            onEvent(.location(category.nameEN))
            var items: [ScanItem] = []

            for target in category.targets {
                let base = Self.expand(target.path)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: base.path, isDirectory: &isDir), isDir.boolValue else { continue }

                let children = (try? fm.contentsOfDirectory(
                    at: base,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: []
                )) ?? []

                for child in children {
                    // Scope filter.
                    if case .matching(let globs) = target.scope,
                       !Self.matches(child.lastPathComponent, globs: globs) {
                        continue
                    }

                    // SAFETY GATE: skip anything the policy refuses (outside allowed
                    // roots, protected, resolves through a symlink to elsewhere, ...).
                    if policy.validate(child) != nil { continue }

                    // Age filter.
                    let modDate = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate
                    if let minAge = target.minAgeDays, let modDate {
                        let ageDays = now.timeIntervalSince(modDate) / 86_400
                        if ageDays < Double(minAge) { continue }
                    }

                    let size = Self.allocatedSize(of: child)
                    let item = ScanItem(
                        url: child,
                        categoryID: category.id,
                        sizeBytes: size,
                        modificationDate: modDate
                    )
                    items.append(item)
                    onEvent(.item(item))
                }
            }

            onEvent(.categoryDone(ScanResultGroup(
                category: category,
                items: items.sorted { $0.sizeBytes > $1.sizeBytes }
            )))
        }
    }

    // MARK: - Helpers

    /// Expand a leading `~` to the user's home directory.
    static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    static func matches(_ name: String, globs: [String]) -> Bool {
        globs.contains { pattern in
            pattern.withCString { p in
                name.withCString { s in fnmatch(p, s, 0) == 0 }
            }
        }
    }

    /// Recursive on-disk (allocated) size in bytes. Only regular files count.
    static func allocatedSize(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
        ]

        func fileSize(_ f: URL) -> Int64 {
            guard let v = try? f.resourceValues(forKeys: keys) else { return 0 }
            return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0)
        }

        if !isDir.boolValue {
            return fileSize(url)
        }

        var total: Int64 = 0
        if let en = fm.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],  // do NOT follow symlinks
            errorHandler: nil
        ) {
            for case let f as URL in en {
                let v = try? f.resourceValues(forKeys: keys)
                if v?.isRegularFile == true {
                    total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? v?.fileSize ?? 0)
                }
            }
        }
        return total
    }
}
