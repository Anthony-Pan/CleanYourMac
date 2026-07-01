import SwiftUI
import AppKit
import CleanCore

/// The Large & Old Files screen: find the biggest, least-used files in the
/// user's content folders and move the ones they pick to the Trash. Nothing is
/// ever selected automatically — these are the user's own documents.
struct LargeFilesView: View {
    @Bindable var model: LargeFilesViewModel
    @State private var showConfirm = false

    init(model: LargeFilesViewModel) { self.model = model }

    private var busy: Bool { model.phase == .scanning || model.phase == .cleaning }

    var body: some View {
        ZStack {
            StageBackground(glow: busy)

            switch model.phase {
            case .idle, .scanning, .cleaning:
                busyView
            case .done:
                doneView
            case .results:
                resultsView
            }
        }
        .navigationTitle("Large & Old Files")
        .task { if model.phase == .idle { await model.scan() } }
    }

    // MARK: - Busy

    private var busyView: some View {
        VStack(spacing: 16) {
            ReclaimGauge(bytes: model.selectedBytes, scanning: true, done: false)
            Text(model.phase == .cleaning ? "Moving to Trash…" : "Scanning your files…")
                .foregroundStyle(Palette.muted)
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Palette.accent)
                .shadow(color: Palette.accent.opacity(0.5), radius: 20)
            Text("Done!")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)
            Text("Freed \(ByteFormat.human(model.lastReport?.freedBytes ?? 0)) · moved \(model.lastReport?.trashed.count ?? 0) files to Trash")
                .foregroundStyle(Palette.muted)
            if let report = model.lastReport, !report.failed.isEmpty || !report.blocked.isEmpty {
                Text("\(report.failed.count + report.blocked.count) file(s) couldn’t be moved and were left untouched.")
                    .font(.caption)
                    .foregroundStyle(Palette.champagne)
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
            filterBar
            safetyBanner

            if model.visibleFiles.isEmpty {
                emptyState
            } else {
                fileList
                cleanBar
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("LARGE & OLD FILES")
                .font(.system(size: 11, weight: .semibold)).tracking(1.6)
                .foregroundStyle(Palette.muted)
            Text("\(ByteFormat.human(model.visibleBytes)) in \(model.visibleFiles.count) files")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)
            Text("Your biggest files across Downloads, Documents, Desktop, Movies, Music and Pictures.")
                .font(.callout)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var filterBar: some View {
        // Horizontally scrollable so the four controls never clip at the
        // minimum window width (they don't all fit on one line at 920pt).
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                SegmentedPicker(selection: $model.sizeFilter,
                                options: LargeFilesViewModel.SizeFilter.allCases,
                                label: \.label)
                SegmentedPicker(selection: $model.ageFilter,
                                options: LargeFilesViewModel.AgeFilter.allCases,
                                label: \.label)
                typeMenu
                sortMenu
            }
            .padding(.horizontal, 22)
        }
        .padding(.bottom, 10)
    }

    private var typeMenu: some View {
        Menu {
            Button {
                model.typeFilter = []
            } label: {
                Label("All types", systemImage: model.typeFilter.isEmpty ? "checkmark" : "")
            }
            Divider()
            ForEach(model.availableKinds, id: \.self) { kind in
                Button {
                    if model.typeFilter.contains(kind) { model.typeFilter.remove(kind) }
                    else { model.typeFilter.insert(kind) }
                } label: {
                    Label(kind.titleEN, systemImage: model.typeFilter.contains(kind) ? "checkmark" : kind.symbol)
                }
            }
        } label: {
            pillLabel(systemImage: "line.3.horizontal.decrease.circle",
                      text: model.typeFilter.isEmpty ? "All types" : "\(model.typeFilter.count) types")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var sortMenu: some View {
        Menu {
            ForEach(LargeFilesViewModel.SortOrder.allCases) { order in
                Button {
                    model.sort = order
                } label: {
                    Label(order.label, systemImage: model.sort == order ? "checkmark" : "")
                }
            }
        } label: {
            pillLabel(systemImage: "arrow.up.arrow.down", text: model.sort.label)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func pillLabel(systemImage: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 12))
            Text(text).font(.system(size: 12, weight: .medium))
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(Palette.ink2)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Palette.glassBorder, lineWidth: 1))
    }

    private var safetyBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 12))
                .foregroundStyle(Palette.champagne)
            Text("These are your personal files. Nothing is selected for you — review each one. Removed files go to the Trash and can be restored.")
                .font(.caption)
                .foregroundStyle(Palette.ink2.opacity(0.9))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.champagne.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.champagne.opacity(0.25), lineWidth: 1))
        .padding(.horizontal, 22)
        .padding(.bottom, 10)
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                selectAllRow
                Rectangle().fill(Palette.hair).frame(height: 1).padding(.leading, 44)
                ForEach(Array(model.visibleFiles.enumerated()), id: \.element.id) { index, file in
                    LargeFileRow(file: file,
                                 selected: model.isSelected(file.id),
                                 now: Date()) {
                        model.toggle(file.id)
                    }
                    if index < model.visibleFiles.count - 1 {
                        Rectangle().fill(Palette.hair).frame(height: 1).padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 4)
            .glassCard(radius: 18)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private var selectAllRow: some View {
        Button { model.toggleAllVisible() } label: {
            HStack(spacing: 10) {
                Image(systemName: model.allVisibleSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(model.allVisibleSelected ? Palette.accent : .white.opacity(0.28))
                Text(model.allVisibleSelected ? "Deselect all shown" : "Select all shown")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Palette.ink2)
                Spacer()
                Text("\(model.visibleFiles.count) files")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            .padding(.vertical, 8).padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var cleanBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(model.selectedCount) files selected")
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
            "Move \(model.selectedCount) files (\(ByteFormat.human(model.selectedBytes))) to the Trash?",
            isPresented: $showConfirm, titleVisibility: .visible
        ) {
            Button("Move to Trash") { Task { await model.clean() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These are your personal files. Nothing is deleted permanently — you can restore everything from the Trash.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 40)).foregroundStyle(Palette.muted.opacity(0.5))
            Text("No files match these filters.")
                .foregroundStyle(Palette.muted)
            Text("Try a smaller size or a wider age range.")
                .font(.caption).foregroundStyle(Palette.muted.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
    }
}

// MARK: - Segmented pill picker (theme-matched, replaces system Picker chrome)

private struct SegmentedPicker<Option: Identifiable & Equatable>: View {
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let on = option == selection
                Button { selection = option } label: {
                    Text(label(option))
                        .font(.system(size: 11.5, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.black.opacity(0.85) : Palette.ink2.opacity(0.8))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(
                            Capsule().fill(on ? AnyShapeStyle(Palette.accentLinear) : AnyShapeStyle(Color.clear))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Palette.glassBorder, lineWidth: 1))
    }
}

// MARK: - One file row

private struct LargeFileRow: View {
    let file: LargeFile
    let selected: Bool
    let now: Date
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Palette.accent : .white.opacity(0.28))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(file.name)
            .accessibilityValue(selected ? "Selected for removal" : "Not selected")

            Image(systemName: file.kind.symbol)
                .font(.system(size: 15))
                .foregroundStyle(Palette.ink2.opacity(0.7))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text(file.name)
                        .font(.callout)
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let age = ageBadge { Badge(text: age, color: Palette.champagne) }
                }
                Text(file.path)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(ByteFormat.human(file.sizeBytes))
                .font(.caption).monospacedDigit()
                .foregroundStyle(Palette.muted)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
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

    /// Show an age chip only for genuinely old files ("2y", "8mo", "140d").
    private var ageBadge: String? {
        guard let days = file.ageDays(now: now), days >= 180 else { return nil }
        if days >= 365 { return "\(days / 365)y" }
        return "\(days / 30)mo"
    }
}

// MARK: - Reused small badge (mirrors the uninstaller's)

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
