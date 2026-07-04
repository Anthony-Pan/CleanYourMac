import SwiftUI
import AppKit
import CleanCore

/// The Uninstaller screen: discover installed apps, review each app's bundle
/// plus its attributed leftover files, and move the selected items to the Trash.
struct UninstallerView: View {
    @Bindable var model: UninstallViewModel

    init(model: UninstallViewModel) { self.model = model }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Uninstaller") {
                searchField
                statusPill
            }

            switch model.phase {
            case .idle, .scanning:
                loadingList
            case .ready:
                subtitleLine
                appList
            }
        }
        .navigationTitle("Uninstaller")
        .task { if model.phase == .idle { await model.scan() } }
    }

    // MARK: - Top bar pieces

    @ViewBuilder private var statusPill: some View {
        if model.phase == .ready {
            StatusPill(text: "\(model.visibleApps.count) apps", tone: .blue)
        } else {
            StatusPill(text: "Scanning…", tone: .blue)
        }
    }

    private var subtitleLine: some View {
        Text("Remove an app together with the caches, preferences and support files it leaves behind.")
            .font(.system(size: 12.5))
            .foregroundStyle(Palette.sub)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 26)
            .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.sub)
            TextField("Search apps", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(.white)
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.sub)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Palette.glassBorder, lineWidth: 1))
        .frame(width: 220)
    }

    // MARK: - Lists

    private var loadingList: some View {
        VStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.05))
                    .frame(height: 62)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Palette.glassBorder, lineWidth: 1))
            }
            Spacer()
        }
        .padding(.horizontal, 26)
        .padding(.top, 4)
    }

    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(model.visibleApps) { app in
                    AppUninstallRow(app: app, model: model)
                }
                if model.visibleApps.isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34)).foregroundStyle(Palette.tiny)
            Text(model.query.isEmpty ? "No apps found." : "No apps match “\(model.query)”.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.sub)
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
        .glassCard(radius: 14, focused: expanded)
    }

    private var header: some View {
        Button { withAnimation(.snappy) { model.toggleExpanded(app) } } label: {
            HStack(spacing: 12) {
                AppIcon(url: app.url).frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(app.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        statusBadge
                    }
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tiny)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Text(ByteFormat.human(app.sizeBytes))
                    .font(.system(size: 13)).monospacedDigit()
                    .foregroundStyle(Palette.sub)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.sub)
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
            TagBadge(text: "System", color: Color.white.opacity(0.55))
        } else if model.isSelf(app) {
            TagBadge(text: "This app", color: Color.white.opacity(0.55))
        } else if model.isRunning(app) {
            TagBadge(text: "Running", color: PillTone.warn.text)
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
                    Text("Finding leftover files…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.sub)
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
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(PillTone.warn.text)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) item\(count == 1 ? "" : "s") couldn’t be moved to the Trash.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                Text("They may be in use (quit “\(app.name)” first) or protected by the safety check. Nothing else was affected.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.sub)
            }
            Spacer()
        }
        .padding(14)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hair).frame(height: 1) }
    }

    private var protectedNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.white.opacity(0.85))
            Text(app.isSystem
                 ? "This is a system app and is protected — it can’t be uninstalled here."
                 : "CleanYourMac can’t uninstall itself.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink2)
            Spacer()
        }
        .padding(16)
    }

    private func leftoverList(_ plan: UninstallPlan) -> some View {
        LazyVStack(spacing: 0) {
            if model.isRunning(app) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(PillTone.warn.text)
                    Text("“\(app.name)” is running. Quit it first so its settings aren’t rewritten.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.ink2)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
            }
            ForEach(Array(plan.leftovers.enumerated()), id: \.element.id) { index, leftover in
                if index > 0 {
                    Rectangle().fill(Palette.hair).frame(height: 1)
                        .padding(.leading, 14)
                }
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
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.selectedCount(for: app)) of \(plan.leftovers.count) items selected")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.sub)
                Text("Everything goes to the Trash — fully recoverable.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)
            }
            Spacer()
            uninstallButton
        }
        .padding(14)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hair).frame(height: 1) }
    }

    private var uninstallButton: some View {
        GradientButton(
            title: "Uninstall · \(ByteFormat.human(model.selectedBytes(for: app)))",
            disabled: model.selectedCount(for: app) == 0
        ) {
            showConfirm = true
        }
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
            GlassCheckbox(on: selected, action: onToggle)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text(leftover.kind.titleEN)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.85))
                    if leftover.confidence == .medium {
                        TagBadge(text: "review", color: PillTone.warn.text)
                    }
                }
                Text(leftover.url.path)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(ByteFormat.human(leftover.sizeBytes))
                .font(.system(size: 13)).monospacedDigit()
                .foregroundStyle(Palette.sub)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([leftover.url])
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.sub)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 14)
    }
}

// MARK: - Small pieces

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
