import Foundation

// MARK: - Model

/// One launchd job definition (a `*.plist`) found in a startup directory.
public struct StartupItem: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable, CaseIterable {
        /// `~/Library/LaunchAgents` — runs as the logged-in user at login.
        case userAgent
        /// `/Library/LaunchAgents` — third-party, runs for every user at login.
        case systemAgent
        /// `/Library/LaunchDaemons` — third-party, runs as root at boot.
        case systemDaemon
    }

    public let url: URL
    public let label: String
    public let kind: Kind
    /// Absolute path of the launched binary: `Program`, or `ProgramArguments[0]`.
    public let executable: String?
    public let runAtLoad: Bool?
    public let disabled: Bool?
    /// True when the label or the plist filename carries the `com.apple.`
    /// prefix — items macOS itself installs, noise for most users.
    public let isApple: Bool

    public var id: String { url.path }
    public var path: String { url.path }

    public init(
        url: URL,
        label: String,
        kind: Kind,
        executable: String?,
        runAtLoad: Bool?,
        disabled: Bool?,
        isApple: Bool
    ) {
        self.url = url
        self.label = label
        self.kind = kind
        self.executable = executable
        self.runAtLoad = runAtLoad
        self.disabled = disabled
        self.isApple = isApple
    }
}

/// Everything one read produced.
public struct StartupItemsReport: Sendable {
    public let items: [StartupItem]
    /// Plist files that exist but could not be parsed — skipped, but counted
    /// so the UI can say the list may be incomplete.
    public let unreadableCount: Int

    public init(items: [StartupItem], unreadableCount: Int) {
        self.items = items
        self.unreadableCount = unreadableCount
    }
}

// MARK: - Reader

/// Lists launchd job definitions from the startup directories.
///
/// READ-ONLY by design: this type has no code path that writes, moves, or
/// deletes anything — it only lists directories and parses plists. The
/// directories are injectable for tests; production uses the fixed launchd
/// locations, never paths derived from user input.
public struct StartupItemsReader: Sendable {
    public struct Location: Sendable {
        public let directory: URL
        public let kind: StartupItem.Kind

        public init(directory: URL, kind: StartupItem.Kind) {
            self.directory = directory
            self.kind = kind
        }
    }

    public let locations: [Location]

    public init(locations: [Location]) {
        self.locations = locations
    }

    /// The three fixed launchd directories the Optimization module reviews.
    public static func production() -> StartupItemsReader {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return StartupItemsReader(locations: [
            Location(directory: home.appendingPathComponent("Library/LaunchAgents"),
                     kind: .userAgent),
            Location(directory: URL(fileURLWithPath: "/Library/LaunchAgents"),
                     kind: .systemAgent),
            Location(directory: URL(fileURLWithPath: "/Library/LaunchDaemons"),
                     kind: .systemDaemon),
        ])
    }

    /// Missing directories contribute nothing; malformed plists are skipped
    /// and counted. Items come back in location order, filename-sorted within
    /// each directory so results are deterministic.
    public func read() -> StartupItemsReport {
        let fm = FileManager.default
        var items: [StartupItem] = []
        var unreadable = 0

        for location in locations {
            let entries = (try? fm.contentsOfDirectory(
                at: location.directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where entry.pathExtension.lowercased() == "plist" {
                if let item = Self.parse(entry, kind: location.kind) {
                    items.append(item)
                } else {
                    unreadable += 1
                }
            }
        }

        return StartupItemsReport(items: items, unreadableCount: unreadable)
    }

    // MARK: - Parsing

    /// `nil` when the file cannot be read or is not a dictionary-shaped plist.
    /// A parseable plist without a `Label` keeps its filename as the label —
    /// still worth showing, since the file is what actually sits on disk.
    static func parse(_ url: URL, kind: StartupItem.Kind) -> StartupItem? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any] else {
            return nil
        }

        let filename = url.deletingPathExtension().lastPathComponent
        let label = (dict["Label"] as? String) ?? filename
        // launchd prefers `Program` when both keys are present.
        let executable = (dict["Program"] as? String)
            ?? (dict["ProgramArguments"] as? [Any])?.first as? String

        return StartupItem(
            url: url,
            label: label,
            kind: kind,
            executable: executable,
            runAtLoad: dict["RunAtLoad"] as? Bool,
            disabled: dict["Disabled"] as? Bool,
            isApple: label.hasPrefix("com.apple.") || filename.hasPrefix("com.apple.")
        )
    }
}
