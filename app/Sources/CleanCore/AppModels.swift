import Foundation

// MARK: - Installed application

/// An application discovered on this Mac that the uninstaller can act on.
/// Read-only value type produced by `AppDiscovery`.
public struct InstalledApp: Identifiable, Sendable, Hashable {
    /// The `.app` bundle on disk.
    public let url: URL
    /// Display name (`CFBundleDisplayName` → `CFBundleName` → file name).
    public let name: String
    /// `CFBundleIdentifier` (e.g. `com.foo.Bar`). Nil when the bundle has none.
    public let bundleID: String?
    /// `CFBundleShortVersionString`, if present.
    public let version: String?
    /// On-disk (allocated) size of the bundle, in bytes.
    public let sizeBytes: Int64
    /// True for Apple / system apps (`com.apple.*` or under `/System`). These are
    /// never uninstallable — the plan is empty and the UI must refuse them.
    public let isSystem: Bool

    public var id: String { url.path }

    public init(
        url: URL,
        name: String,
        bundleID: String?,
        version: String?,
        sizeBytes: Int64,
        isSystem: Bool
    ) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.version = version
        self.sizeBytes = sizeBytes
        self.isSystem = isSystem
    }
}

// MARK: - Leftover files

/// One concrete file or directory attributed to an app, eligible for removal.
public struct AppLeftover: Identifiable, Sendable, Hashable {
    /// Where the leftover lives, used for grouping and labelling.
    public enum Kind: String, Sendable, CaseIterable {
        case bundle              // the .app itself
        case applicationSupport  // ~/Library/Application Support/<id|name>
        case caches              // ~/Library/Caches/<id|name>
        case preferences         // ~/Library/Preferences/<id>.plist (+ ByHost)
        case containers          // ~/Library/Containers/<id>
        case groupContainers     // ~/Library/Group Containers/<team>.<id>
        case savedState          // ~/Library/Saved Application State/<id>.savedState
        case logs                // ~/Library/Logs/<id|name>
        case httpStorages        // ~/Library/HTTPStorages/<id>
        case webKit              // ~/Library/WebKit/<id>
        case cookies             // ~/Library/Cookies/<id>.binarycookies
        case launchAgents        // ~/Library/LaunchAgents/<id>*.plist
        case applicationScripts  // ~/Library/Application Scripts/<id>
    }

    /// How the leftover was attributed to the app. Bundle-ID matches are exact;
    /// name matches are heuristic and should be reviewed before removal.
    public enum Confidence: String, Sendable {
        case high    // matched the app's bundle identifier exactly
        case medium  // matched the app's display name (heuristic)
    }

    public let url: URL
    public let kind: Kind
    public let confidence: Confidence
    public let sizeBytes: Int64

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }

    public init(url: URL, kind: Kind, confidence: Confidence, sizeBytes: Int64) {
        self.url = url
        self.kind = kind
        self.confidence = confidence
        self.sizeBytes = sizeBytes
    }
}

public extension AppLeftover.Kind {
    var titleEN: String {
        switch self {
        case .bundle:             return "Application"
        case .applicationSupport: return "Application Support"
        case .caches:             return "Caches"
        case .preferences:        return "Preferences"
        case .containers:         return "Container"
        case .groupContainers:    return "Group Container"
        case .savedState:         return "Saved State"
        case .logs:               return "Logs"
        case .httpStorages:       return "Web Storage"
        case .webKit:             return "WebKit Data"
        case .cookies:            return "Cookies"
        case .launchAgents:       return "Launch Agent"
        case .applicationScripts: return "Application Scripts"
        }
    }

    var titleCN: String {
        switch self {
        case .bundle:             return "应用程序"
        case .applicationSupport: return "应用支持文件"
        case .caches:             return "缓存"
        case .preferences:        return "偏好设置"
        case .containers:         return "沙盒容器"
        case .groupContainers:    return "共享容器"
        case .savedState:         return "窗口状态"
        case .logs:               return "日志"
        case .httpStorages:       return "网页存储"
        case .webKit:             return "WebKit 数据"
        case .cookies:            return "Cookie"
        case .launchAgents:       return "启动代理"
        case .applicationScripts: return "应用脚本"
        }
    }
}

// MARK: - Removal plan

/// The complete, reviewable removal plan for one app: the bundle plus every
/// leftover we could attribute to it. Purely descriptive — building a plan never
/// touches the filesystem.
public struct UninstallPlan: Identifiable, Sendable {
    public let app: InstalledApp
    /// Removable items, with the `.app` bundle first when present.
    public let leftovers: [AppLeftover]

    public var id: String { app.id }
    public var totalBytes: Int64 { leftovers.reduce(0) { $0 + $1.sizeBytes } }

    /// Leftovers other than the bundle itself.
    public var extras: [AppLeftover] { leftovers.filter { $0.kind != .bundle } }
    public var extraBytes: Int64 { extras.reduce(0) { $0 + $1.sizeBytes } }
    /// True when we found associated files beyond the app bundle.
    public var hasExtras: Bool { !extras.isEmpty }

    public init(app: InstalledApp, leftovers: [AppLeftover]) {
        self.app = app
        self.leftovers = leftovers
    }
}
