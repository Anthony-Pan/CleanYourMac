import Foundation
import UniformTypeIdentifiers

// MARK: - Large / old file

/// One large regular file found in the user's content folders, eligible for
/// review. Read-only value type produced by `FileFinder`.
///
/// Unlike caches, these are the user's *own* documents — irreplaceable. The UI
/// therefore never selects them automatically; every file is opt-in and still
/// goes to the Trash (recoverable) when removed.
public struct LargeFile: Identifiable, Sendable, Hashable {
    /// Where the file lives.
    public let url: URL
    /// On-disk (allocated) size in bytes.
    public let sizeBytes: Int64
    /// Last content modification date, if known.
    public let modificationDate: Date?
    /// Last content access ("opened") date, if the filesystem reports it.
    public let accessDate: Date?
    /// Coarse type bucket used for the icon, grouping and the type filter.
    public let kind: FileKind

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public var path: String { url.path }
    /// The immediate containing folder's name (e.g. "Downloads"), for context.
    public var parentName: String { url.deletingLastPathComponent().lastPathComponent }

    public init(
        url: URL,
        sizeBytes: Int64,
        modificationDate: Date?,
        accessDate: Date?,
        kind: FileKind
    ) {
        self.url = url
        self.sizeBytes = sizeBytes
        self.modificationDate = modificationDate
        self.accessDate = accessDate
        self.kind = kind
    }

    /// The most recent of `modificationDate` and `accessDate`. This is the date
    /// used to judge how "old" a file is. Using the later of the two is
    /// deliberately conservative — a recently *read* file is not old, so fewer
    /// files qualify as old (safer). Returns `nil` when neither date is known.
    public var lastUsedDate: Date? {
        switch (modificationDate, accessDate) {
        case let (m?, a?): return max(m, a)
        case let (m?, nil): return m
        case let (nil, a?): return a
        case (nil, nil): return nil
        }
    }

    /// Whole days since the file was last used (the more recent of modification
    /// date and access date), or `nil` when neither date is known. Judging age by
    /// the most recent of the two dates is conservative — a recently read file is
    /// not "old", so fewer files qualify.
    public func ageDays(now: Date = Date()) -> Int? {
        guard let lastUsedDate else { return nil }
        return max(0, Int(now.timeIntervalSince(lastUsedDate) / 86_400))
    }

    /// True if the file hasn't been used (modified or accessed) in at least
    /// `days` days. Uses `lastUsedDate` (the more recent of modified/accessed) so
    /// a file that was read recently is never judged old.
    public func isOlder(thanDays days: Int, now: Date = Date()) -> Bool {
        guard let age = ageDays(now: now) else { return false }
        return age >= days
    }
}

// MARK: - Scan location policy

/// Guards which folders a user may add as custom scan roots.
///
/// Safety rationale: this prevents obviously dangerous directories (system
/// folders, ~/Library, home root, etc.) from being enrolled before the user
/// even starts a scan. The per-file `SafetyPolicy` gate still re-validates
/// every path at removal time — this is an early, user-friendly layer on top.
public enum ScanLocationPolicy {
    /// Returns a human-readable English refusal reason if `url` must not be
    /// added as a scan root, or `nil` when the folder is acceptable.
    ///
    /// Validates after canonicalizing (resolving symlinks) so a symlink cannot
    /// smuggle in a protected path.
    public static func validate(_ url: URL) -> String? {
        let fm = FileManager.default
        let canonical = url.canonicalized

        // Must exist and be a directory.
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: canonical.path, isDirectory: &isDir) else {
            return "This folder doesn't exist."
        }
        guard isDir.boolValue else {
            return "Please choose a folder, not a file."
        }

        let path = canonical.path

        // Reject filesystem root.
        if path == "/" {
            return "The filesystem root cannot be a scan location."
        }

        // Reject system-protected trees (exact match or anything inside them).
        let systemRoots = [
            "/System", "/Library", "/usr", "/bin", "/sbin",
            "/etc", "/var", "/private", "/opt", "/cores",
        ]
        for root in systemRoots {
            if path == root || path.hasPrefix(root + "/") {
                return "System folders cannot be added as scan locations."
            }
        }

        // Reject /Users and /Applications themselves; subfolders are fine.
        if path == "/Users" || path == "/Applications" {
            return "Choose a specific folder inside \(canonical.lastPathComponent), not the folder itself."
        }

        let home = fm.homeDirectoryForCurrentUser.canonicalized
        let homePath = home.path

        // Reject the home directory itself (the default scan already covers its
        // content subfolders — pointing at the whole home would be too broad).
        if path == homePath {
            return "The default scan already covers your home's content folders — pick a subfolder instead."
        }

        // Reject ~/Library and anything inside it.
        let libraryPath = home.appendingPathComponent("Library").canonicalized.path
        if path == libraryPath || path.hasPrefix(libraryPath + "/") {
            return "Library folders are excluded from scanning for safety."
        }

        // Reject ~/.Trash and anything inside it.
        let trashPath = home.appendingPathComponent(".Trash").canonicalized.path
        if path == trashPath || path.hasPrefix(trashPath + "/") {
            return "The Trash cannot be added as a scan location."
        }

        return nil
    }
}

// MARK: - Coarse file type

/// A small, user-legible set of buckets. Deliberately coarse — the point is a
/// friendly icon and a "show only videos/archives/…" filter, not a MIME table.
public enum FileKind: String, Sendable, CaseIterable {
    case video, audio, image, archive, diskImage, document, developer, other

    public var titleEN: String {
        switch self {
        case .video:     return "Videos"
        case .audio:     return "Audio"
        case .image:     return "Images"
        case .archive:   return "Archives"
        case .diskImage: return "Disk Images"
        case .document:  return "Documents"
        case .developer: return "Developer"
        case .other:     return "Other"
        }
    }

    public var titleCN: String {
        switch self {
        case .video:     return "视频"
        case .audio:     return "音频"
        case .image:     return "图片"
        case .archive:   return "压缩包"
        case .diskImage: return "磁盘映像"
        case .document:  return "文档"
        case .developer: return "开发文件"
        case .other:     return "其他"
        }
    }

    public var symbol: String {
        switch self {
        case .video:     return "film.fill"
        case .audio:     return "music.note"
        case .image:     return "photo.fill"
        case .archive:   return "doc.zipper"
        case .diskImage: return "opticaldiscdrive.fill"
        case .document:  return "doc.text.fill"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .other:     return "doc.fill"
        }
    }

    /// Infer a bucket from a resolved `UTType` (preferred) and fall back to the
    /// filename extension when the type is unknown.
    public static func infer(contentType: UTType?, url: URL) -> FileKind {
        if let type = contentType, let kind = fromType(type) { return kind }
        let ext = url.pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext), let kind = fromType(type) {
            return kind
        }
        return fromExtension(ext.lowercased())
    }

    private static func fromType(_ type: UTType) -> FileKind? {
        if type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audiovisualContent) {
            return .video
        }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .diskImage) { return .diskImage }
        if type.conforms(to: .archive) || type.conforms(to: .gzip) || type.conforms(to: .bz2) || type.conforms(to: .zip) {
            return .archive
        }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) || type.conforms(to: .shellScript) {
            return .developer
        }
        if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .content)
            || type.conforms(to: .spreadsheet) || type.conforms(to: .presentation) {
            return .document
        }
        return nil
    }

    /// Extension fallback for types `UTType` can't resolve (e.g. unusual archive
    /// or disk-image suffixes).
    private static func fromExtension(_ ext: String) -> FileKind {
        let table: [FileKind: Set<String>] = [
            .video: ["mp4", "mov", "m4v", "mkv", "avi", "wmv", "flv", "webm", "mpg", "mpeg", "ts"],
            .audio: ["mp3", "m4a", "aac", "flac", "wav", "aiff", "ogg", "wma"],
            .image: ["jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "bmp", "raw", "psd", "webp"],
            .archive: ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz", "zst"],
            .diskImage: ["dmg", "iso", "sparseimage", "sparsebundle", "img", "pkg"],
            .document: ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "rtf", "csv", "epub"],
            .developer: ["swift", "c", "cpp", "h", "m", "mm", "js", "ts", "py", "go", "rs", "java", "kt", "json", "xcarchive"],
        ]
        for (kind, exts) in table where exts.contains(ext) { return kind }
        return .other
    }
}
