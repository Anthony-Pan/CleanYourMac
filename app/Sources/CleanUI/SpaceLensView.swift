import SwiftUI
import AppKit
import CleanCore

/// The Space Lens module: a read-only folder-size explorer. Scans a folder,
/// ranks its children by size and lets the user drill into subfolders with a
/// breadcrumb trail back out. Nothing is ever deleted from this screen.
struct SpaceLensView: View {
    let model: SpaceLensViewModel

    init(model: SpaceLensViewModel) { self.model = model }

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .idle:
                idleView
            case .scanning:
                scanningView
            case .results:
                resultsView
            }
        }
        .navigationTitle("Space Lens")
    }

    // MARK: - Idle (start screen with a Scan button)

    private var idleView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Space Lens") { StatusPill(text: "Read-only", tone: .good) }

            Spacer()

            Orb(size: 230)

            Text("See where your space went")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 6)

            Text("Explore your home folder and rank every file and folder by size. Space Lens only looks — it never deletes anything.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.sub)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 8)

            CTACircle(title: "Scan") { model.startScan() }
                .padding(.top, 30)

            Spacer()
        }
    }

    // MARK: - Scanning (live sizing)

    private var scanningView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Space Lens") { StatusPill(text: "Scanning…", tone: .blue) }

            Spacer()

            Orb(size: 230, animating: true)
                .overlay(
                    VStack(spacing: 3) {
                        Text("SIZED SO FAR")
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(1.3)
                            .foregroundStyle(Palette.slab)
                        Text(ByteFormat.human(model.sizedBytes))
                            .font(.system(size: 32, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: model.sizedBytes)
                    }
                )

            Text(model.currentChildName.isEmpty
                 ? "Sizing \(model.currentFolderName)…"
                 : "Sizing \(model.currentChildName) · \(model.entries.count) items sized")
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(Palette.sub)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 380)
                .padding(.top, 16)

            GhostButton(title: "Stop") { model.cancelScan() }
                .padding(.top, 24)

            Spacer()
        }
    }

    // MARK: - Results (breadcrumb + ranked rows)

    private var resultsView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Space Lens") {
                if model.wasCancelled {
                    StatusPill(text: "Partial — scan stopped early", tone: .warn)
                } else {
                    StatusPill(text: "\(model.entries.count) items · \(ByteFormat.human(model.totalBytes))",
                               tone: .blue)
                }
            }

            breadcrumbBar

            if model.deniedCurrentFolder {
                emptyState(
                    icon: "lock.fill",
                    title: "This folder can't be read",
                    message: "macOS denied access to \(model.currentFolderName). Grant Full Disk Access in System Settings, or step back and explore another folder.")
            } else if model.entries.isEmpty {
                emptyState(
                    icon: "folder",
                    title: model.wasCancelled ? "Scan stopped" : "Nothing here",
                    message: model.wasCancelled
                        ? "The scan was stopped before anything was sized. Rescan to size this folder."
                        : "\(model.currentFolderName) is empty.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.entries) { entry in
                            entryRow(entry)
                        }
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 4)
                    .padding(.bottom, 14)
                }
            }

            BottomBar {
                Text("Read-only — Space Lens never deletes anything.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.sub)

                Spacer()

                GhostButton(title: "Rescan") { model.rescanCurrentFolder() }
            }
        }
    }

    // MARK: Breadcrumbs

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(model.pathStack.enumerated()), id: \.offset) { index, url in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.tiny)
                    }
                    crumb(url, index: index)
                }
            }
            .padding(.horizontal, 26)
        }
        .frame(height: 34)
    }

    private func crumb(_ url: URL, index: Int) -> some View {
        let isCurrent = index == model.pathStack.count - 1
        return Button { model.jump(to: index) } label: {
            Text(model.crumbTitle(for: url))
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? Palette.ink : Palette.sub)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(hex: Onyx.cream, alpha: isCurrent ? 0.08 : 0)))
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
    }

    // MARK: Rows

    private func entryRow(_ entry: SpaceLensEntry) -> some View {
        let drillable = model.isDrillable(entry)
        let isLargest = entry.id == model.entries.first?.id
        return HStack(spacing: 12) {
            iconTile(for: entry)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                RelativeSizeBar(value: entry.sizeBytes, max: model.largestBytes)
                if let subtitle = subtitle(for: entry) {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tiny)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(model.percentOfTotal(entry))
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.sub)
                .frame(width: 40, alignment: .trailing)

            SizeText(entry.sizeBytes, emphasized: isLargest)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.sub)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")

            // Cleared (not removed) on leaf rows so trailing columns align.
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(drillable ? Palette.sub : .clear)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(radius: 14)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { if drillable { model.open(entry) } }
    }

    private func subtitle(for entry: SpaceLensEntry) -> String? {
        guard entry.isDirectory else { return nil }
        let items = entry.itemCount.map { $0 == 1 ? "1 item" : "\($0) items" }
        guard entry.isPackage else { return items }
        return (["Package"] + (items.map { [$0] } ?? [])).joined(separator: " · ")
    }

    private func iconTile(for entry: SpaceLensEntry) -> some View {
        let style = iconStyle(for: entry)
        return RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(style.gradient)
            .frame(width: 32, height: 32)
            .overlay(Image(systemName: style.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white))
    }

    private func iconStyle(for entry: SpaceLensEntry) -> (symbol: String, gradient: LinearGradient) {
        if entry.isPackage { return ("shippingbox.fill", Self.clay) }
        if entry.isDirectory { return ("folder.fill", Self.champagne) }
        return ("doc", Self.warmGrey)
    }

    // Warm, desaturated tile tones matching the Onyx category styles.
    private static let champagne = LinearGradient(
        colors: [Color(hex: 0xD8C49A), Color(hex: 0xB79E72)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    private static let clay = LinearGradient(
        colors: [Color(hex: 0xCE9A78), Color(hex: 0xA66B4E)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    private static let warmGrey = LinearGradient(
        colors: [Color(hex: 0x9A928A), Color(hex: 0x655F59)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: Empty / denied states

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Palette.sub)
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.sub)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
