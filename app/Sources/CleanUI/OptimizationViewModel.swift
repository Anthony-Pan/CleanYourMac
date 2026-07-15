import Foundation
import Observation
import AppKit
import CleanCore

/// Drives the Optimization screen: a read-only review of what launches at
/// startup. Nothing here modifies the system — the model only lists launchd
/// plists and offers reveal-in-Finder / System Settings shortcuts. There is
/// deliberately no clean/delete path in this module.
@MainActor
@Observable
final class OptimizationViewModel {
    enum Phase: Equatable {
        case idle, scanning, results
    }

    private(set) var phase: Phase = .idle
    private(set) var items: [StartupItem] = []
    /// Plist files that exist but could not be parsed — surfaced so the list
    /// never silently claims to be complete.
    private(set) var unreadableCount = 0
    /// Apple-owned items are noise for most users; hidden by default.
    var showApple = false

    private let reader: StartupItemsReader

    init() {
        reader = .production()
    }

    /// Preloaded results state for design snapshots — zero disk access (the
    /// reader is given no locations, so even a stray review reads nothing).
    init(mockItems: [StartupItem], mockUnreadableCount: Int = 0) {
        reader = StartupItemsReader(locations: [])
        items = mockItems
        unreadableCount = mockUnreadableCount
        phase = .results
    }

    // MARK: - Grouped sections

    struct Section: Identifiable {
        let kind: StartupItem.Kind
        let title: String
        let subtitle: String
        let items: [StartupItem]

        var id: String { kind.rawValue }
    }

    /// Visible rows grouped in fixed display order (user agents, system
    /// agents, system daemons). Sections with nothing to show are omitted.
    var sections: [Section] {
        StartupItem.Kind.allCases.compactMap { kind in
            let visible = items.filter { $0.kind == kind && (showApple || !$0.isApple) }
            guard !visible.isEmpty else { return nil }
            return Section(kind: kind,
                           title: Self.title(for: kind),
                           subtitle: Self.subtitle(for: kind),
                           items: visible)
        }
    }

    static func title(for kind: StartupItem.Kind) -> String {
        switch kind {
        case .userAgent: return "Login & user agents"
        case .systemAgent: return "System agents"
        case .systemDaemon: return "System daemons"
        }
    }

    static func subtitle(for kind: StartupItem.Kind) -> String {
        switch kind {
        case .userAgent: return "run when you log in"
        case .systemAgent: return "run for every user"
        case .systemDaemon: return "run as root at boot"
        }
    }

    // MARK: - Derived counts

    var thirdPartyCount: Int { items.filter { !$0.isApple }.count }
    var appleCount: Int { items.filter(\.isApple).count }
    var visibleCount: Int { sections.reduce(0) { $0 + $1.items.count } }

    // MARK: - Review (read-only scan)

    private var reviewTask: Task<Void, Never>?

    func review() {
        reviewTask?.cancel()
        reviewTask = Task { await runReview() }
    }

    private func runReview() async {
        phase = .scanning
        items = []
        unreadableCount = 0
        let engine = reader

        let report = await Task.detached(priority: .userInitiated) {
            engine.read()
        }.value

        // The read is near-instant; hold the scanning state for a beat so the
        // transition reads as deliberate rather than a flicker.
        try? await Task.sleep(nanoseconds: 450_000_000)
        if Task.isCancelled { return }

        items = report.items
        unreadableCount = report.unreadableCount
        phase = .results
    }

    // MARK: - Shortcuts (never modify anything)

    func reveal(_ item: StartupItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// System Settings → General → Login Items — where startup items can
    /// actually be managed. Falls back to opening System Settings itself so
    /// the button always does something visible.
    func openLoginItemsSettings() {
        let ws = NSWorkspace.shared
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"),
           ws.open(url) {
            return
        }
        if let root = URL(string: "x-apple.systempreferences:") { ws.open(root) }
    }
}
