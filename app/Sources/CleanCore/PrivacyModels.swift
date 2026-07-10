import Foundation

// MARK: - Browser / app

/// A browser, Chromium-embedded app, or macOS subsystem whose privacy traces
/// the Privacy scanner knows how to find. Read-only descriptor — the concrete
/// on-disk locations live in `PrivacyScanner` and its composed sub-scanners.
public enum PrivacyApp: Sendable, Hashable, Identifiable {
    case safari, chrome, edge, brave, vivaldi, firefox
    case arc, opera, operaGX, chromium
    /// macOS shared-file-list recent items (documents, apps, servers).
    case systemRecents
    /// Auto-discovered Chromium-embedded app under `~/Library/Application
    /// Support`, verified by on-disk signature (see `ElectronTraceScanner`).
    case electron(name: String, bundleID: String?)
    /// macOS QuickLook thumbnail cache.
    case quickLook
    /// Per-app saved window/UI state restored on relaunch.
    case savedState
    /// The download-provenance ("where from") quarantine database.
    case quarantine
    /// Shell command history files in the home directory.
    case shellHistory
    /// Crash and diagnostic reports under `~/Library/Logs`.
    case diagnostics

    /// Stable string key — replaces the former `rawValue`. Known cases keep
    /// their old raw strings (`"system-recents"` etc.) so category IDs stay
    /// stable across versions.
    public var key: String {
        switch self {
        case .safari:        return "safari"
        case .chrome:        return "chrome"
        case .edge:          return "edge"
        case .brave:         return "brave"
        case .vivaldi:       return "vivaldi"
        case .firefox:       return "firefox"
        case .arc:           return "arc"
        case .opera:         return "opera"
        case .operaGX:       return "operaGX"
        case .chromium:      return "chromium"
        case .systemRecents: return "system-recents"
        case .electron(let name, _): return "electron:\(name)"
        case .quickLook:     return "quicklook"
        case .savedState:    return "saved-state"
        case .quarantine:    return "download-records"
        case .shellHistory:  return "shell-history"
        case .diagnostics:   return "diagnostics"
        }
    }

    public var id: String { key }

    /// The known browser cases, in scan order — used by the browser scanner
    /// loop in `PrivacyScanner` (replaces the former `allCases`).
    public static let browsers: [PrivacyApp] = [
        .safari, .chrome, .edge, .brave, .vivaldi, .firefox,
        .arc, .opera, .operaGX, .chromium,
    ]

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
        case .electron(let name, _): return name
        case .quickLook:     return "Thumbnail Cache"
        case .savedState:    return "App Window States"
        case .quarantine:    return "Download Records"
        case .shellHistory:  return "Terminal History"
        case .diagnostics:   return "Crash & Diagnostic Reports"
        }
    }

    /// SF Symbol used when no installed-app icon is available.
    public var symbol: String {
        switch self {
        case .safari:        return "safari.fill"
        case .systemRecents: return "clock.arrow.circlepath"
        case .electron:      return "app.dashed"
        case .quickLook:     return "photo.on.rectangle"
        case .savedState:    return "macwindow.on.rectangle"
        case .quarantine:    return "arrow.down.doc.fill"
        case .shellHistory:  return "terminal.fill"
        case .diagnostics:   return "stethoscope"
        default:             return "globe"
        }
    }

    /// Bundle identifiers used to tell whether the browser/app is currently
    /// running (so the UI can ask the user to quit it before clearing locked
    /// files). Empty for the system subsystems — macOS itself owns those files
    /// and is never closed.
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
        case .electron(_, let bundleID):
            return [bundleID].compactMap { $0 }
        case .shellHistory:
            // Common terminals keep history in memory and rewrite the file on
            // exit, so the "quit first" notice must be able to fire for them.
            return ["com.apple.Terminal", "com.googlecode.iterm2",
                    "dev.warp.Warp-Stable", "com.github.wez.wezterm",
                    "io.alacritty", "com.mitchellh.ghostty", "net.kovidgoyal.kitty"]
        case .systemRecents, .quickLook, .savedState,
             .quarantine, .diagnostics:
            return []
        }
    }

    /// True for a browser or Electron app whose own running process rewrites its
    /// trace files, so the user should quit it before clearing. False for the
    /// macOS subsystems (their files are owned by the OS, not a quit-able app).
    public var isBrowserOrApp: Bool {
        switch self {
        case .systemRecents, .quickLook, .savedState,
             .quarantine, .shellHistory, .diagnostics:
            return false
        default:
            return true
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
    /// macOS QuickLook thumbnail cache — rebuilt on demand.
    case thumbnails
    /// Saved window layouts apps restore on relaunch. Opt-in — clearing changes
    /// how apps reopen.
    case windowState = "window-state"
    /// The quarantine database recording where downloads came from.
    case downloadRecords = "download-records"
    /// Shell/REPL command history files. Opt-in — clearing is irreversible
    /// from the shell's point of view.
    case shellHistory = "shell-history"
    /// Crash and diagnostic report files.
    case crashReports = "crash-reports"

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
        case .thumbnails:         return "Thumbnail Cache"
        case .windowState:        return "Window States"
        case .downloadRecords:    return "Where-from Records"
        case .shellHistory:       return "Shell Command History"
        case .crashReports:       return "Crash Reports"
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
        case .thumbnails:         return "缩略图缓存"
        case .windowState:        return "窗口状态"
        case .downloadRecords:    return "下载来源记录"
        case .shellHistory:       return "终端命令历史"
        case .crashReports:       return "崩溃报告"
        }
    }

    public var detailEN: String {
        switch self {
        case .caches:
            return "Cached web files. Rebuilt as you browse."
        case .history:
            return "The list of pages you've visited."
        case .cookies:
            return "Cookies and local login state for sites and apps."
        case .sessions:
            return "The set of tabs restored on next launch."
        case .downloads:
            return "The record of files you've downloaded (not the files themselves)."
        case .siteData:
            return "Local Storage, IndexedDB and offline data. May sign you out and clear unsynced app data."
        case .recentDocuments:
            return "A convenience list of recently opened documents. The files themselves are untouched; the list rebuilds with use."
        case .recentApplications:
            return "A convenience list of recently launched apps. The apps themselves are untouched; the list rebuilds with use."
        case .recentServers:
            return "A convenience list of recently connected servers. The list rebuilds with use."
        case .appRecents:
            return "Per-application recent-file lists. The files themselves are untouched; some entries may only clear after the app or Finder restarts."
        case .thumbnails:
            return "Previews macOS generated for your documents and images. Rebuilt on demand."
        case .windowState:
            return "Saved window layouts apps restore on relaunch. Apps will open fresh windows."
        case .downloadRecords:
            return "The database recording where every downloaded file came from."
        case .shellHistory:
            return "Commands you typed in Terminal. Clearing cannot be undone from the shell."
        case .crashReports:
            return "Crash and diagnostic logs. They can contain file paths and app data."
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
        case .thumbnails:         return "photo.stack"
        case .windowState:        return "macwindow"
        case .downloadRecords:    return "arrow.down.circle.dotted"
        case .shellHistory:       return "terminal"
        case .crashReports:       return "doc.badge.gearshape"
        }
    }

    /// True when clearing this kind signs the user out of websites. Both cookies
    /// and site data (Local Storage / IndexedDB) hold login tokens.
    public var signsOut: Bool { [.cookies, .siteData].contains(self) }

    /// A short, honest note about the disruption clearing this causes, or `nil`
    /// when it is low-impact.
    public var impactNote: String? {
        switch self {
        case .cookies:      return "Signs you out"
        case .siteData:     return "May sign you out"
        case .sessions:     return "Forgets your open tabs"
        case .windowState:  return "Apps forget window layout"
        case .shellHistory: return "Clears your command history"
        default:            return nil
        }
    }

    /// Whether the item is pre-selected. Low-impact traces (cache, history,
    /// download list, recents, thumbnails, crash reports) are on by default;
    /// disruptive ones (cookies → sign-outs, sessions → lost tabs, siteData →
    /// sign-outs, windowState → lost layouts, shellHistory → irreversible)
    /// are opt-in.
    public var defaultOn: Bool {
        switch self {
        case .caches, .history, .downloads,
             .recentDocuments, .recentApplications, .recentServers, .appRecents,
             .thumbnails, .downloadRecords, .crashReports:
            return true
        case .cookies, .sessions, .siteData, .windowState, .shellHistory:
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
    /// Profile name for non-default Chromium profiles (e.g. "Profile 1"), the
    /// Firefox profile folder name when more than one profile exists, or the
    /// partition name for Electron `Partitions/` tiers. `nil` for single-profile
    /// browsers and for all system-level items.
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

/// All privacy traces found for one browser, app, or macOS subsystem.
public struct PrivacyGroup: Identifiable, Sendable {
    public let app: PrivacyApp
    public let items: [PrivacyItem]

    public var id: String { app.key }
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }

    public init(app: PrivacyApp, items: [PrivacyItem]) {
        self.app = app
        self.items = items
    }
}
