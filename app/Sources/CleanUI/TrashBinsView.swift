import SwiftUI
import AppKit
import CleanCore

/// The Trash Bins module: review what is sitting in the Trash and permanently
/// remove the selection. This is the one module where deletion is NOT
/// recoverable — the items were already deleted once — so every piece of copy
/// says "permanent" instead of the usual "recoverable from the Trash".
struct TrashBinsView: View {
    let model: TrashBinsViewModel
    @State private var showConfirm = false

    init(model: TrashBinsViewModel) { self.model = model }

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .idle:
                idleView
            case .scanning:
                scanningView
            case .cleaning:
                cleaningView
            case .done:
                doneView
            case .results:
                if model.items.isEmpty { emptyView } else { resultsView }
            }
        }
        .navigationTitle("Trash Bins")
    }

    // MARK: - Idle (start screen with a Scan button)

    private var idleView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Trash Bins") { StatusPill(text: "Ready", tone: .blue) }

            Spacer()

            Orb(size: 230)

            Text("Review and empty your Trash")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 6)

            Text("See what's still sitting in your Trash — and how much space it holds — before anything is gone for good.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.sub)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 8)

            CTACircle(title: "Scan Trash") { model.startScan() }
                .padding(.top, 30)

            Spacer()

            HStack(spacing: 14) {
                if let report = model.lastReport {
                    StatCard(label: "Last emptied",
                             value: ByteFormat.human(report.freedBytes),
                             detail: "removed permanently")
                }
                StatCard(label: "Heads up",
                         value: "Permanent",
                         detail: "items here are already deleted once",
                         valueColor: PillTone.warn.text)
                StatCard(label: "Scope",
                         value: "User Trash",
                         detail: "external-volume trashes not included")
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 26)
            .padding(.bottom, 26)
        }
    }

    // MARK: - Scanning (live byte counter)

    private var scanningView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Trash Bins") { StatusPill(text: "Scanning…", tone: .blue) }

            Spacer()

            Orb(size: 230, animating: true)
                .overlay(
                    VStack(spacing: 3) {
                        Text("IN THE TRASH")
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(1.3)
                            .foregroundStyle(Palette.slab)
                        Text(ByteFormat.human(model.scannedBytes))
                            .font(.system(size: 32, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: model.scannedBytes)
                    }
                )

            Text("Sizing what you threw away · \(model.foundCount) items found")
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(Palette.sub)
                .padding(.top, 16)

            GhostButton(title: "Stop") { model.cancelScan() }
                .padding(.top, 24)

            Spacer()
        }
    }

    // MARK: - Cleaning (permanent removal in progress)

    private var cleaningView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Trash Bins") { StatusPill(text: "Deleting…", tone: .warn) }

            Spacer()

            Orb(size: 230, animating: true)

            Text("Deleting permanently…")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 6)

            Text("Removing \(model.selectedCount) items (\(ByteFormat.human(model.selectedBytes))) from your Trash — this cannot be undone.")
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(Palette.sub)
                .padding(.top, 8)

            SweepBar()
                .padding(.top, 18)

            Spacer()
        }
    }

    // MARK: - Done

    /// Items the last pass could not remove — failed plus safety-blocked.
    private var skippedCount: Int {
        model.lastReport.map { $0.failed.count + $0.blocked.count } ?? 0
    }

    private var doneView: some View {
        let skipped = skippedCount
        var summary = "Freed \(ByteFormat.human(model.lastReport?.freedBytes ?? 0)) · \(model.lastReport?.removed.count ?? 0) items permanently removed"
        if skipped > 0 { summary += " · \(skipped) items could not be removed" }
        return VStack(spacing: 0) {
            TopBar(title: "Trash Bins") {
                if skipped > 0 {
                    StatusPill(text: "\(skipped) skipped", tone: .warn)
                } else {
                    StatusPill(text: "Trash emptied", tone: .good)
                }
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.45), radius: 18)

            Text(skipped > 0 ? "Emptied with \(skipped) items skipped" : "Trash emptied!")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 18)

            Text(summary)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.sub)
                .padding(.top, 6)

            CTACircle(title: "Scan Again") { model.startScan() }
                .padding(.top, 30)

            Spacer()
        }
    }

    // MARK: - Empty state (nothing in the Trash)

    private var emptyView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Trash Bins") { StatusPill(text: "Trash is empty", tone: .good) }

            Spacer()

            Image(systemName: "trash")
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.65))

            Text("Your Trash is empty")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 18)

            Text("Nothing is waiting here — no space left to reclaim.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.sub)
                .padding(.top, 6)

            GhostButton(title: "Scan Again") { model.startScan() }
                .padding(.top, 26)

            Spacer()
        }
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Trash Bins") {
                if model.selectedCount > 0 {
                    StatusPill(text: "\(model.selectedCount) selected — permanent", tone: .warn)
                } else {
                    StatusPill(text: "Nothing selected", tone: .blue)
                }
            }

            heroHeader
            itemList

            BottomBar {
                Text(model.selectedCount == 0
                     ? "Nothing selected — pick what should go for good."
                     : "\(model.selectedCount) of \(model.items.count) items · \(ByteFormat.human(model.selectedBytes)) selected · deletion is permanent")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.sub)

                Spacer()

                GhostButton(title: "Rescan") { model.startScan() }

                GradientButton(title: "Empty Trash (\(model.selectedCount))",
                               disabled: model.selectedCount == 0) { showConfirm = true }
            }
        }
        .confirmationDialog(
            "Permanently delete \(model.selectedCount) items (\(ByteFormat.human(model.selectedBytes)))?",
            isPresented: $showConfirm, titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) { Task { await model.emptyTrash() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These items are already in the Trash, so this deletes them permanently. They CANNOT be recovered — there is no undo, unlike everywhere else in this app.")
        }
    }

    /// Hero total: what is currently selected, live — the same number the
    /// Empty Trash button acts on.
    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ByteFormat.human(model.selectedBytes))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: model.selectedBytes)
            Text("selected in \(model.selectedCount) of \(model.items.count) items · removal is permanent, not recoverable")
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(Palette.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                selectAllRow
                ForEach(model.items) { item in
                    itemRow(item)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 2)
            .padding(.bottom, 16)
        }
    }

    /// Tri-state master checkbox above the list.
    private var selectAllRow: some View {
        Button { model.toggleAll() } label: {
            HStack(spacing: 12) {
                GlassCheckbox(state: model.allSelectedState) { model.toggleAll() }
                Text(model.allSelectedState == .on ? "Deselect all" : "Select all")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.ink2)
                Spacer()
                Text("\(model.items.count) items · \(ByteFormat.human(model.totalBytes))")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Palette.tiny)
            }
            .padding(.vertical, 9).padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(radius: 14)
    }

    /// Biggest item — the shared denominator for every row's size bar. The
    /// list is sorted largest-first, so it's simply the first.
    private var maxItemBytes: Int64 {
        model.items.first?.sizeBytes ?? 0
    }

    private func itemRow(_ item: TrashItem) -> some View {
        HStack(spacing: 12) {
            GlassCheckbox(on: model.isSelected(item.id)) { model.toggle(item.id) }
                .accessibilityLabel(item.name)
                .accessibilityValue(model.isSelected(item.id)
                    ? "Selected for permanent deletion" : "Not selected")

            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                RelativeSizeBar(value: item.sizeBytes, max: maxItemBytes)
                    .padding(.top, 3)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                SizeText(item.sizeBytes, emphasized: item.id == model.items.first?.id)
                if let date = item.modificationDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.tiny)
                }
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.sub)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .glassCard(radius: 14)
    }
}
