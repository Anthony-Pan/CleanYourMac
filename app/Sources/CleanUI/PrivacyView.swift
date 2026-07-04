import SwiftUI
import AppKit
import CleanCore

/// The Privacy screen: find browser traces and macOS recent-item lists (caches,
/// history, cookies, sessions, download lists, site data, recents) and move the
/// selected ones to the Trash. Disruptive traces (cookies, site data, open tabs)
/// are opt-in and clearly labelled.
struct PrivacyView: View {
    let model: PrivacyViewModel
    @State private var showConfirm = false
    @State private var fdaBannerDismissed = false

    private static let theme: ModuleTheme = .blue

    init(model: PrivacyViewModel) { self.model = model }

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                idleView
            case .scanning, .cleaning:
                busyView
            case .done:
                doneView
            case .results:
                resultsView
            }
        }
        .navigationTitle("Privacy")
        .onChange(of: model.phase) { _, newPhase in
            // Reset the FDA banner dismissal when a new scan starts so the user
            // sees a fresh prompt if FDA is still missing after re-scanning.
            if newPhase == .scanning { fdaBannerDismissed = false }
        }
    }

    // MARK: - Idle (start screen with a Scan button)

    private var idleView: some View {
        VStack(spacing: 0) {
            Spacer()

            HeroBlob(theme: Self.theme, symbol: "hand.raised.fill")

            Text("Privacy")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Palette.ink)
                .padding(.top, 26)

            Text("Clear caches, history, cookies and recent-item lists left behind by your browsers and macOS.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 8)

            Spacer()

            CircleActionButton(title: "Scan", theme: Self.theme) {
                Task { await model.scan() }
            }
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Busy

    private var busyView: some View {
        VStack(spacing: 0) {
            Spacer()

            HeroBlob(theme: Self.theme, symbol: "hand.raised.fill", animating: true)

            Text(model.phase == .cleaning ? "Clearing traces…" : "Scanning…")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .padding(.top, 26)

            Spacer()

            CircleActionButton(title: model.phase == .scanning ? "Scanning" : "Clearing",
                               theme: Self.theme,
                               ring: .progress,
                               disabled: true) {}
                .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.45), radius: 22)

            Text("Traces cleared")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Palette.ink)
                .padding(.top, 20)

            Text("Freed \(ByteFormat.human(model.lastReport?.freedBytes ?? 0)) · moved \(model.lastReport?.trashed.count ?? 0) items to Trash")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .padding(.top, 8)

            if let report = model.lastReport, !report.failed.isEmpty || !report.blocked.isEmpty {
                Text("\(report.failed.count + report.blocked.count) item(s) couldn't be cleared — quit the browser and try again.")
                    .font(.caption)
                    .foregroundStyle(Palette.warn)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }

            Spacer()

            CircleActionButton(title: "Scan Again", theme: Self.theme) {
                Task { await model.scan() }
            }
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            header

            if model.fdaMissing && !fdaBannerDismissed {
                fdaBanner
            }

            if model.groups.isEmpty {
                emptyState
            } else {
                groupList
                bottomAction
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("PRIVACY")
                .font(.system(size: 11, weight: .semibold)).tracking(1.6)
                .foregroundStyle(Palette.muted)
            Text("\(ByteFormat.human(model.totalBytes)) of browser traces")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)
            Text("Clear caches, history, cookies and recent-item lists left by your browsers and macOS. Sign-out and site-data traces are off by default.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var fdaBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(Palette.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text("Safari data needs Full Disk Access")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text("Grant it in System Settings › Privacy & Security, then scan again.")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            Button("Open Settings") {
                // swiftlint:disable:next force_unwrapping
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button(action: { fdaBannerDismissed = true }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassCard(radius: 12)
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }

    private var groupList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(model.groups) { group in
                    PrivacyGroupCard(group: group, model: model)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
    }

    private var bottomAction: some View {
        VStack(spacing: 10) {
            Text("\(model.selectedRowCount) traces · \(ByteFormat.human(model.selectedBytes)) selected")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))

            CircleActionButton(title: "Clean",
                               theme: Self.theme,
                               disabled: model.selectedCount == 0) {
                showConfirm = true
            }
        }
        .padding(.bottom, 24)
        .confirmationDialog(
            "Clear \(model.selectedRowCount) traces (\(ByteFormat.human(model.selectedBytes)))?",
            isPresented: $showConfirm, titleVisibility: .visible
        ) {
            Button("Move to Trash") { Task { await model.clean() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    /// The confirmation body, spelling out the disruptive consequences of the
    /// *specific* selection (sign-outs, lost tabs) at the last, riskiest step —
    /// not just at the checkbox.
    private var confirmMessage: String {
        var parts = ["Nothing is deleted permanently — you can restore everything from the Trash."]
        if model.selectedSignsOut { parts.append("Clearing cookies or site data may sign you out of websites.") }
        if model.selectedLosesTabs { parts.append("Clearing sessions will forget your open tabs.") }
        parts.append("Quit your browsers first so their files aren't rewritten.")
        return parts.joined(separator: " ")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 40)).foregroundStyle(Palette.muted.opacity(0.5))
            Text("No browser traces found.")
                .foregroundStyle(Palette.muted)
            Text("Safari data requires Full Disk Access — grant it in System Settings › Privacy & Security, then scan again.")
                .font(.caption).foregroundStyle(Palette.muted.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
    }
}

// MARK: - One browser / system card

private struct PrivacyGroupCard: View {
    let group: PrivacyGroup
    let model: PrivacyViewModel

    var body: some View {
        let rows = model.aggregatedRows(for: group)
        VStack(spacing: 0) {
            header(rows: rows)
            Rectangle().fill(Palette.hair).frame(height: 1)
            if model.isRunning(group.app) { runningNotice }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                AggregatedPrivacyRow(row: row,
                                     selected: model.isSelected(aggregatedRow: row)) {
                    model.toggle(aggregatedRow: row)
                }
                if index < rows.count - 1 {
                    Rectangle().fill(Palette.hair).frame(height: 1).padding(.leading, 44)
                }
            }
        }
        .glassCard(radius: 14)
    }

    private func header(rows: [AggregatedRow]) -> some View {
        HStack(spacing: 12) {
            BrowserIconView(app: group.app)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(group.app.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    if model.isRunning(group.app) {
                        TagBadge(text: "Running")
                    }
                }
                Text("\(model.selectedRowCount(in: group)) of \(rows.count) selected · \(ByteFormat.human(group.totalBytes))")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }

            Spacer()

            GlassPill(title: allSelected ? "Deselect all" : "Select all") {
                model.toggleGroup(group)
            }
        }
        .padding(14)
    }

    private var allSelected: Bool {
        let ids = group.items.map(\.id)
        return !ids.isEmpty && ids.allSatisfy { model.isSelected($0) }
    }

    private var runningNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warn)
            Text("“\(group.app.displayName)” is running. Quit it first so its files aren’t rewritten.")
                .font(.caption).foregroundStyle(Palette.ink2)
            Spacer()
            Button("Quit") {
                model.quit(group.app)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hair).frame(height: 1).padding(.leading, 44)
        }
    }
}

// MARK: - Aggregated trace row

/// One row per (kind, context) pair, showing the summed size of all underlying
/// files. Its checkbox toggles all underlying item ids together.
private struct AggregatedPrivacyRow: View {
    let row: AggregatedRow
    let selected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? .white : .white.opacity(0.28))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.kind.titleEN)
            .accessibilityValue(selected ? "Selected" : "Not selected")

            Image(systemName: row.kind.symbol)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text(row.kind.titleEN)
                        .font(.callout)
                        .foregroundStyle(Palette.ink2)
                    if let ctx = row.context {
                        TagBadge(text: ctx)
                    }
                    if let note = row.kind.impactNote {
                        TagBadge(text: note)
                    }
                }
                Text(row.kind.detailEN)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            Text(ByteFormat.human(row.totalSize))
                .font(.caption).monospacedDigit()
                .foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
    }
}

// MARK: - Real browser icon (falls back to an SF Symbol if not installed)

private struct BrowserIconView: View {
    let app: PrivacyApp
    var body: some View {
        if let image = BrowserIcon.image(for: app) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.12))
                .overlay(Image(systemName: app.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.85)))
        }
    }
}

private enum BrowserIcon {
    private static let cache = NSCache<NSString, NSImage>()

    /// The installed browser's Finder icon, resolved from its bundle id and
    /// cached. `nil` when the browser can't be located (including `systemRecents`,
    /// which has no bundle IDs — the SF-Symbol fallback handles that).
    static func image(for app: PrivacyApp) -> NSImage? {
        let key = app.rawValue as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let ws = NSWorkspace.shared
        let url = app.bundleIDs.lazy
            .compactMap { ws.urlForApplication(withBundleIdentifier: $0) }
            .first
        guard let url else { return nil }
        let icon = ws.icon(forFile: url.path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}
