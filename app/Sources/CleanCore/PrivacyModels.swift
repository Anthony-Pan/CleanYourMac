import Foundation

// MARK: - Browser

/// A browser whose privacy traces the Privacy scanner knows how to find.
/// Read-only descriptor — the concrete on-disk locations live in
/// `PrivacyScanner`.
public enum PrivacyApp: String, Sendable, CaseIterable, Identifiable {
    case safari, chrome, edge, brave, vivaldi, firefox

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .safari:  return "Safari"
        case .chrome:  return "Google Chrome"
        case .edge:    return "Microsoft Edge"
        case .brave:   return "Brave"
        case .vivaldi: return "Vivaldi"
        case .firefox: return "Firefox"
        }
    }

    public var symbol: String {
        switch self {
        case .safari:  return "safari.fill"
        default:       return "globe"
        }
    }

    /// Bundle identifiers used to tell whether the browser is currently running
    /// (so the UI can ask the user to quit it before clearing locked files).
    public var bundleIDs: [String] {
        switch self {
        case .safari:  return ["com.apple.Safari"]
        case .chrome:  return ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary"]
        case .edge:    return ["com.microsoft.edgemac"]
        case .brave:   return ["com.brave.Browser"]
        case .vivaldi: return ["com.vivaldi.Vivaldi"]
        case .firefox: return ["org.mozilla.firefox"]
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

    public var titleEN: String {
        switch self {
        case .caches:    return "Cache"
        case .history:   return "Browsing History"
        case .cookies:   return "Cookies"
        case .sessions:  return "Open Tabs / Session"
        case .downloads: return "Download History"
        }
    }

    public var titleCN: String {
        switch self {
        case .caches:    return "缓存"
        case .history:   return "浏览历史"
        case .cookies:   return "Cookie"
        case .sessions:  return "打开的标签页 / 会话"
        case .downloads: return "下载历史"
        }
    }

    public var detailEN: String {
        switch self {
        case .caches:    return "Cached web files. Rebuilt as you browse."
        case .history:   return "The list of pages you've visited."
        case .cookies:   return "Site cookies and local login state."
        case .sessions:  return "The set of tabs restored on next launch."
        case .downloads: return "The record of files you've downloaded (not the files themselves)."
        }
    }

    public var symbol: String {
        switch self {
        case .caches:    return "internaldrive.fill"
        case .history:   return "clock.arrow.circlepath"
        case .cookies:   return "circle.grid.2x2.fill"
        case .sessions:  return "rectangle.stack.fill"
        case .downloads: return "arrow.down.circle.fill"
        }
    }

    /// True when clearing this signs the user out of websites.
    public var signsOut: Bool { self == .cookies }

    /// A short, honest note about the disruption clearing this causes, or `nil`
    /// when it is low-impact.
    public var impactNote: String? {
        switch self {
        case .cookies:  return "Signs you out of websites"
        case .sessions: return "Forgets your open tabs"
        default:        return nil
        }
    }

    /// Whether the item is pre-selected. Low-impact traces (cache, history,
    /// download list) are on by default; disruptive ones (cookies → sign-outs,
    /// sessions → lost tabs) are opt-in and clearly labelled.
    public var defaultOn: Bool {
        switch self {
        case .caches, .history, .downloads: return true
        case .cookies, .sessions:           return false
        }
    }
}

// MARK: - Privacy item

/// One concrete privacy trace on disk (a file or directory), attributed to a
/// specific browser and category. Produced read-only by `PrivacyScanner`.
public struct PrivacyItem: Identifiable, Sendable, Hashable {
    public let app: PrivacyApp
    public let kind: PrivacyItemKind
    public let url: URL
    public let sizeBytes: Int64

    public var id: String { url.path }
    public var defaultOn: Bool { kind.defaultOn }
    public var signsOut: Bool { kind.signsOut }

    public init(app: PrivacyApp, kind: PrivacyItemKind, url: URL, sizeBytes: Int64) {
        self.app = app
        self.kind = kind
        self.url = url
        self.sizeBytes = sizeBytes
    }
}

// MARK: - Privacy group

/// All privacy traces found for one browser.
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
