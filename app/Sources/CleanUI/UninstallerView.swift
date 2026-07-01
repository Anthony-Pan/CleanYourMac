import SwiftUI
import AppKit
import CleanCore

/// The Uninstaller screen: discover installed apps, review each app's bundle
/// plus its attributed leftover files, and move the selected items to the Trash.
struct UninstallerView: View {
    @State private var model = UninstallViewModel()

    var body: some View {
        ZStack {
            StageBackground(glow: model.phase == .scanning)

            VStack(spacing: 0) {
                header

                switch model.phase {
                case .idle, .scanning:
                    loadingList
                case .ready:
                    appList
                }
            }
        }
        .navigationTitle("Uninstaller")
        .task { if model.phase == .idle { await model.scan() } }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("Uninstaller")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text("Remove an app together with the caches, preferences and support files it leaves behind.")
                    .font(.callout)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }

            searchField

            if model.phase == .ready {
                Text("\(model.visibleApps.count) apps · \(ByteFormat.human(model.totalBundleBytes))")
                    .font(.caption)
                    .foregroundStyle(Palette.muted.opacity(0.8))
            }
        }
        .padding(.top, 30)
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
            TextField("Search apps", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Palette.ink)
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassCard(radius: 12)
        .frame(maxWidth: 420)
    }

    // MARK: - Lists

    private var loadingList: some View {
        VStack(spacing: 12) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.04))
                    .frame(height: 66)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.hair, lineWidth: 1))
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
    }

    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(model.visibleApps) { app in
                    AppUninstallRow(app: app, model: model)
                }
                if model.visibleApps.isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34)).foregroundStyle(Palette.muted.opacity(0.5))
            Text(model.query.isEmpty ? "No apps found." : "No apps match “\(model.query)”.")
                .foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 60)
    }
}

// MARK: - One app (expandable → leftover review)

private struct AppUninstallRow: View {
    let app: InstalledApp
    let model: UninstallViewModel
    @State private var showConfirm = false

    private var expanded: Bool { model.isExpanded(app) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded {
                Rectangle().fill(Palette.hair).frame(height: 1)
                expandedBody
            }
        }
        .glassCard(radius: 16, focused: expanded)
    }

    private var header: some View {
        Button { withAnimation(.snappy) { model.toggleExpanded(app) } } label: {
            HStack(spacing: 12) {
                AppIcon(url: app.url).frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(app.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        statusBadge
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Text(ByteFormat.human(app.sizeBytes))
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(Palette.ink2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        let version = app.version.map { "v\($0)" }
        return [version, app.bundleID].compactMap { $0 }.joined(separator: "  ·  ")
    }

    @ViewBuilder private var statusBadge: some View {
        if app.isSystem {
            Badge(text: "System", color: Palette.muted)
        } else if model.isSelf(app) {
            Badge(text: "This app", color: Palette.muted)
        } else if model.isRunning(app) {
            Badge(text: "Running", color: Palette.champagne)
        }
    }

    // MARK: Expanded content

    @ViewBuilder private var expandedBody: some View {
        if app.isSystem || model.isSelf(app) {
            protectedNotice
        } else {
            if model.hasProblems(app), let report = model.report(for: app) {
                problemNotice(report)
            }
            if model.isPlanning(app) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Finding leftover files…").foregroundStyle(Palette.muted)
                }
                .padding(16)
            } else if let plan = model.plan(for: app) {
                leftoverList(plan)
                footer(plan)
            }
        }
    }

    private func problemNotice(_ report: CleanReport) -> some View {
        let count = report.failed.count + report.blocked.count
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.champagne)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) item\(count == 1 ? "" : "s") couldn’t be moved to the Trash.")
                    .font(.callout).foregroundStyle(Palette.ink)
                Text("They may be in use (quit “\(app.name)” first) or protected by the safety check. Nothing else was affected.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer()
        }
        .padding(14)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hair).frame(height: 1) }
    }

    private var protectedNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill").foregroundStyle(Palette.accent)
            Text(app.isSystem
                 ? "This is a system app and is protected — it can’t be uninstalled here."
                 : "CleanYourMac can’t uninstall itself.")
                .font(.callout)
                .foregroundStyle(Palette.ink2)
            Spacer()
        }
        .padding(16)
    }

    private func leftoverList(_ plan: UninstallPlan) -> some View {
        LazyVStack(spacing: 0) {
            if model.isRunning(app) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.champagne)
                    Text("“\(app.name)” is running. Quit it first so its settings aren’t rewritten.")
                        .font(.caption).foregroundStyle(Palette.ink2)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
            }
            ForEach(plan.leftovers) { leftover in
                LeftoverRow(
                    leftover: leftover,
                    selected: model.isSelected(app, leftover.id)
                ) { model.toggle(app, leftover.id) }
            }
        }
        .padding(.vertical, 4)
    }

    private func footer(_ plan: UninstallPlan) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(model.selectedCount(for: app)) of \(plan.leftovers.count) items selected")
                    .font(.subheadline).foregroundStyle(Palette.ink)
                Text("Everything goes to the Trash — fully recoverable.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer()
            uninstallButton(plan)
        }
        .padding(14)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hair).frame(height: 1) }
    }

    private func uninstallButton(_ plan: UninstallPlan) -> some View {
        let disabled = model.selectedCount(for: app) == 0
        return Button { showConfirm = true } label: {
            Label("Move \(ByteFormat.human(model.selectedBytes(for: app))) to Trash", systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(Palette.accentLinear))
                .shadow(color: Palette.accent.opacity(disabled ? 0 : 0.5), radius: 12, y: 2)
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.4 : 1)
        .disabled(disabled)
        .confirmationDialog(
            "Move \(app.name) and \(model.selectedCount(for: app)) items (\(ByteFormat.human(model.selectedBytes(for: app)))) to the Trash?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Move to Trash") { Task { await model.uninstall(app) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing is deleted permanently — you can restore everything from the Trash.")
        }
    }
}

// MARK: - One leftover file

private struct LeftoverRow: View {
    let leftover: AppLeftover
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

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text(leftover.kind.titleEN)
                        .font(.callout)
                        .foregroundStyle(Palette.ink2)
                    if leftover.confidence == .medium {
                        Badge(text: "review", color: Palette.champagne)
                    }
                }
                Text(leftover.url.path)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(ByteFormat.human(leftover.sizeBytes))
                .font(.caption).monospacedDigit()
                .foregroundStyle(Palette.muted)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([leftover.url])
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 14)
    }
}

// MARK: - Small pieces

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

/// The real Finder icon for an app bundle, cached by path so scrolling and
/// search keystrokes don't re-hit `NSWorkspace` for rows that haven't changed.
private struct AppIcon: View {
    let url: URL
    var body: some View {
        Image(nsImage: IconCache.icon(for: url.path))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }
}

private enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()
    static func icon(for path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
