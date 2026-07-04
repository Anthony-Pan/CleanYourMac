import Foundation

// MARK: - Browser / app

/// A browser or macOS subsystem whose privacy traces the Privacy scanner knows
/// how to find. Read-only descriptor — the concrete on-disk locations live in
/// `PrivacyScanner`.
public enum PrivacyApp: String, Sendable, CaseIterable, Identifiable {
    case safari, chrome, edge, brave, vivaldi, firefox
    case arc, opera, operaGX, chromium
    /// macOS shared-file-list recent items (documents, apps, servers).
    case systemRecents = "system-recents"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .safari:        return "Safari"
        case .chrome:        return "Google Chrome"
        case .edge:          return "Microsoft Edge"
        case .brave:         return "Brave"
        case .vivaldi:       return "Vivaldi"
        case .firefox:       return "Firefox"
        case .arc:           return "Arc"
        case .opera:         return "Opera"
        case .operaGX:       return "Opera GX"
        case .chromium:      return "Chromium"
        case .systemRecents: return "macOS Recent Items"
        }
    }

    /// SF Symbol used when no installed-app icon is available.
    public var symbol: String {
        switch self {
        case .safari:        return "safari.fill"
        case .systemRecents: return "clock.arrow.circlepath"
        default:             return "globe"
        }
    }

    /// Bundle identifiers used to tell whether the browser is currently running
    /// (so the UI can ask the user to quit it before clearing locked files).
    /// Empty for `systemRecents` — the Finder/loginwindow handle those files and
    /// are never closed.
    public var bundleIDs: [String] {
        switch self {
        case .safari:
            return ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
        case .chrome:
            return ["com.google.Chrome", "com.google.Chrome.beta",
                    "com.google.Chrome.dev", "com.google.Chrome.canary"]
        case .edge:
            return ["com.microsoft.edgemac", "com.microsoft.edgemac.Beta",
                    "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary"]
        case .brave:
            return ["com.brave.Browser", "com.brave.Browser.beta",
                    "com.brave.Browser.nightly"]
        case .vivaldi:
            return ["com.vivaldi.Vivaldi"]
        case .firefox:
            return ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
                    "org.mozilla.nightly"]
        case .arc:
            return ["company.thebrowser.Browser"]
        case .opera:
            return ["com.operasoftware.Opera"]
        case .operaGX:
            return ["com.operasoftware.OperaGX"]
        case .chromium:
            return ["org.chromium.Chromium"]
        case .systemRecents:
            return []
        }
    }
}

// MARK: - Privacy item kind

/// The category of trace a `PrivacyItem` represents. Determines its label, the
/// impact of clearing it, and whether it is selected by default.
///
/// Deliberately excludes anything that would lose the user's *content* — saved
/// passwords, autofill/cards, and bookmarks are never offered.
public enum PrivacyItemKind: String, Sendable, CaseIterable {
    case caches, history, cookies, sessions, downloads
    /// Local Storage, IndexedDB, Service Workers, and offline site data.
    /// Opt-in (`defaultOn == false`) because clearing it may sign the user out.
    case siteData = "site-data"
    /// macOS Recents — convenience lists only; the files/apps themselves are kept.
    case recentDocuments = "recent-documents"
    case recentApplications = "recent-applications"
    case recentServers = "recent-servers"
    /// Per-application recent-file registrations under sharedfilelist.
    case appRecents = "app-recents"

    public var titleEN: String {
        switch self {
        case .caches:             return "Cache"
        case .history:            return "Browsing History"
        case .cookies:            return "Cookies"
        case .sessions:           return "Open Tabs / Session"
        case .downloads:          return "Download History"
        case .siteData:           return "Site Data"
        case .recentDocuments:    return "Recent Documents"
        case .recentApplications: return "Recent Applications"
        case .recentServers:      return "Recent Servers"
        case .appRecents:         return "Per-App Recent Files"
        }
    }

    public var titleCN: String {
        switch self {
        case .caches:             return "缓存"
        case .history:            return "浏览历史"
        case .cookies:            return "Cookie"
        case .sessions:           return "打开的标签页 / 会话"
        case .downloads:          return "下载历史"
        case .siteData:           return "网站数据"
        case .recentDocuments:    return "最近使用的文档"
        case .recentApplications: return "最近使用的应用"
        case .recentServers:      return "最近连接的服务器"
        case .appRecents:         return "各应用最近文件列表"
        }
    }

    public var detailEN: String {
        switch self {
        case .caches:
            return "Cached web files. Rebuilt as you browse."
        case .history:
            return "The list of pages you've visited."
        case .cookies:
            return "Site cookies and local login state."
        case .sessions:
            return "The set of tabs restored on next launch."
        case .downloads:
            return "The record of files you've downloaded (not the files themselves)."
        case .siteData:
            return "Local Storage, IndexedDB and offline site data. Sites may sign you out."
        case .recentDocuments:
            return "A convenience list of recently opened documents. The files themselves are untouched; the list rebuilds with use."
        case .recentApplications:
            return "A convenience list of recently launched apps. The apps themselves are untouched; the list rebuilds with use."
        case .recentServers:
            return "A convenience list of recently connected servers. The list rebuilds with use."
        case .appRecents:
            return "Per-application recent-file lists. The files themselves are untouched; some entries may only clear after the app or Finder restarts."
        }
    }

    public var symbol: String {
        switch self {
        case .caches:             return "internaldrive.fill"
        case .history:            return "clock.arrow.circlepath"
        case .cookies:            return "circle.grid.2x2.fill"
        case .sessions:           return "rectangle.stack.fill"
        case .downloads:          return "arrow.down.circle.fill"
        case .siteData:           return "cylinder.split.1x2.fill"
        case .recentDocuments:    return "doc.text.fill"
        case .recentApplications: return "square.grid.2x2.fill"
        case .recentServers:      return "network"
        case .appRecents:         return "tray.full.fill"
        }
    }

    /// True when clearing this kind signs the user out of websites. Both cookies
    /// and site data (Local Storage / IndexedDB) hold login tokens.
    public var signsOut: Bool { [.cookies, .siteData].contains(self) }

    /// A short, honest note about the disruption clearing this causes, or `nil`
    /// when it is low-impact.
    public var impactNote: String? {
        switch self {
        case .cookies:  return "Signs you out of websites"
        case .siteData: return "Sites may sign you out"
        case .sessions: return "Forgets your open tabs"
        default:        return nil
        }
    }

    /// Whether the item is pre-selected. Low-impact traces (cache, history,
    /// download list, recents) are on by default; disruptive ones (cookies → sign-
    /// outs, sessions → lost tabs, siteData → sign-outs) are opt-in.
    public var defaultOn: Bool {
        switch self {
        case .caches, .history, .downloads,
             .recentDocuments, .recentApplications, .recentServers, .appRecents:
            return true
        case .cookies, .sessions, .siteData:
            return false
        }
    }
}

// MARK: - Privacy item

/// One concrete privacy trace on disk (a file or directory), attributed to a
/// specific browser/app and category. Produced read-only by `PrivacyScanner`.
public struct PrivacyItem: Identifiable, Sendable, Hashable {
    public let app: PrivacyApp
    public let kind: PrivacyItemKind
    public let url: URL
    public let sizeBytes: Int64
    /// Profile name for non-default Chromium profiles (e.g. "Profile 1"), or the
    /// Firefox profile folder name when more than one profile exists. `nil` for
    /// single-profile browsers and for all system-level items.
    public let context: String?

    public var id: String { url.path }
    public var defaultOn: Bool { kind.defaultOn }
    public var signsOut: Bool { kind.signsOut }

    public init(
        app: PrivacyApp,
        kind: PrivacyItemKind,
        url: URL,
        sizeBytes: Int64,
        context: String? = nil
    ) {
        self.app = app
        self.kind = kind
        self.url = url
        self.sizeBytes = sizeBytes
        self.context = context
    }
}

// MARK: - Privacy group

/// All privacy traces found for one browser or macOS subsystem.
public struct PrivacyGroup: Identifiable, Sendable {
    public let app: PrivacyApp
    public let items: [PrivacyItem]

    public var id: String { app.rawValue }
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }

    public init(app: PrivacyApp, items: [PrivacyItem]) {
        self.app = app
        self.items = items
    }
}
