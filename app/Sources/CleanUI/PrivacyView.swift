import SwiftUI
import AppKit
import CleanCore

/// The Privacy screen: find browser traces (caches, history, cookies, sessions,
/// download lists) and move the selected ones to the Trash. Disruptive traces
/// (cookies, open tabs) are opt-in and clearly labelled.
struct PrivacyView: View {
    let model: PrivacyViewModel
    @State private var showConfirm = false

    init(model: PrivacyViewModel) { self.model = model }

    private var busy: Bool { model.phase == .scanning || model.phase == .cleaning }

    var body: some View {
        ZStack {
            StageBackground(glow: busy)

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
    }

    // MARK: - Idle (start screen with a Scan button)

    private var idleView: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 15)
                Circle()
                    .fill(RadialGradient(colors: [Palette.accent.opacity(0.18), .clear],
                                         center: .center, startRadius: 20, endRadius: 130))
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Palette.accent)
            }
            .frame(width: 214, height: 214)

            VStack(spacing: 6) {
                Text("Privacy")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text("Clear caches, history and cookies left behind by your browsers.")
                    .font(.callout)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            Button { Task { await model.scan() } } label: {
                Label("Scan", systemImage: "magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 40)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Palette.accentLinear))
                    .shadow(color: Palette.accent.opacity(0.5), radius: 16, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(40)
    }

    // MARK: - Busy

    private var busyView: some View {
        VStack(spacing: 16) {
            ReclaimGauge(bytes: model.selectedBytes, scanning: true, done: false)
            Text(model.phase == .cleaning ? "Clearing traces…" : "Scanning browsers…")
                .foregroundStyle(Palette.muted)
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 72))
                .foregroundStyle(Palette.accent)
                .shadow(color: Palette.accent.opacity(0.5), radius: 20)
            Text("Traces cleared")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)
            Text("Freed \(ByteFormat.human(model.lastReport?.freedBytes ?? 0)) · moved \(model.lastReport?.trashed.count ?? 0) items to Trash")
                .foregroundStyle(Palette.muted)
            if let report = model.lastReport, !report.failed.isEmpty || !report.blocked.isEmpty {
                Text("\(report.failed.count + report.blocked.count) item(s) couldn’t be cleared — quit the browser and try again.")
                    .font(.caption)
                    .foregroundStyle(Palette.champagne)
                    .multilineTextAlignment(.center)
            }
            Button("Scan Again") { Task { await model.scan() } }
                .controlSize(.large)
                .tint(Palette.accent)
                .padding(.top, 6)
        }
        .padding(40)
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            header

            if model.groups.isEmpty {
                emptyState
            } else {
                groupList
                cleanBar
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("PRIVACY")
                .font(.system(size: 11, weight: .semibold)).tracking(1.6)
                .foregroundStyle(Palette.muted)
            Text("\(ByteFormat.human(model.totalBytes)) of browser traces")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)
            Text("Clear caches, history and cookies from your browsers. Sign-out and open-tab data is off by default.")
                .font(.callout)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
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

    private var cleanBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(model.selectedCount) traces selected")
                    .font(.subheadline).foregroundStyle(Palette.ink)
                Text("Everything goes to the Trash — recoverable")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer()
            CleanButton(size: model.selectedBytes, disabled: model.selectedCount == 0) { showConfirm = true }
        }
        .padding(16)
        .background(Palette.bg.opacity(0.55))
        .overlay(alignment: .top) { Rectangle().fill(Palette.hair).frame(height: 1) }
        .confirmationDialog(
            "Clear \(model.selectedCount) traces (\(ByteFormat.human(model.selectedBytes)))?",
            isPresented: $showConfirm, titleVisibility: .visible
        ) {
            Button("Move to Trash") { Task { await model.clean() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing is deleted permanently — you can restore everything from the Trash. Quit your browsers first so their files aren’t rewritten.")
        }
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

// MARK: - One browser card

private struct PrivacyGroupCard: View {
    let group: PrivacyGroup
    let model: PrivacyViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Palette.hair).frame(height: 1)
            if model.isRunning(group.app) { runningNotice }
            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                PrivacyItemRow(item: item,
                               selected: model.isSelected(item.id)) {
                    model.toggle(item.id)
                }
                if index < group.items.count - 1 {
                    Rectangle().fill(Palette.hair).frame(height: 1).padding(.leading, 44)
                }
            }
        }
        .glassCard(radius: 16)
    }

    private var header: some View {
        HStack(spacing: 12) {
            BrowserIconView(app: group.app)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(group.app.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    if model.isRunning(group.app) {
                        Badge(text: "Running", color: Palette.champagne)
                    }
                }
                Text("\(model.selectedCount(in: group)) of \(group.items.count) selected · \(ByteFormat.human(group.totalBytes))")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }

            Spacer()

            Button { model.toggleGroup(group) } label: {
                Text(allSelected ? "Deselect all" : "Select all")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }

    private var allSelected: Bool {
        let ids = group.items.map(\.id)
        return !ids.isEmpty && ids.allSatisfy { model.isSelected($0) }
    }

    private var runningNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.champagne)
            Text("“\(group.app.displayName)” is running. Quit it first so its files aren’t rewritten.")
                .font(.caption).foregroundStyle(Palette.ink2)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hair).frame(height: 1).padding(.leading, 44) }
    }
}

// MARK: - One trace row

private struct PrivacyItemRow: View {
    let item: PrivacyItem
    let selected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Palette.accent : .white.opacity(0.28))
            }
            .buttonStyle(.plain)

            Image(systemName: item.kind.symbol)
                .font(.system(size: 14))
                .foregroundStyle(Palette.ink2.opacity(0.7))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text(item.kind.titleEN)
                        .font(.callout)
                        .foregroundStyle(Palette.ink2)
                    if let note = item.kind.impactNote {
                        Badge(text: note, color: Palette.champagne)
                    }
                }
                Text(item.kind.detailEN)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            Text(ByteFormat.human(item.sizeBytes))
                .font(.caption).monospacedDigit()
                .foregroundStyle(Palette.muted)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
    }
}

// MARK: - Small badge (mirrors the uninstaller's)

private struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
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
                .fill(Palette.accent.opacity(0.15))
                .overlay(Image(systemName: app.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.accent))
        }
    }
}

private enum BrowserIcon {
    private static let cache = NSCache<NSString, NSImage>()

    /// The installed browser's Finder icon, resolved from its bundle id and
    /// cached. `nil` when the browser can't be located.
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
