import SwiftUI
import AppKit
import CleanCore

/// The Mail Attachments module: finds the local copies Apple Mail keeps of
/// downloaded/viewed attachments and moves the reviewed selection to the
/// Trash. The originals stay with their messages, so the copies are safe to
/// remove.
struct MailAttachmentsView: View {
    let model: MailAttachmentsViewModel
    @State private var showConfirm = false

    init(model: MailAttachmentsViewModel) { self.model = model }

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
                resultsView
            }
        }
        .navigationTitle("Mail Attachments")
    }

    // MARK: - Idle (start screen with a Scan button)

    private var idleView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Mail Attachments") { StatusPill(text: "Ready", tone: .blue) }

            Spacer()

            Orb(size: 230)

            Text("Reclaim space from Mail downloads")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 6)

            Text("Mail keeps local copies of attachments you've opened or saved. The originals stay with their messages, so these copies are safe to remove.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.sub)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .padding(.top, 8)

            CTACircle(title: "Scan") { model.startScan() }
                .padding(.top, 30)

            Spacer()

            HStack(spacing: 14) {
                if let report = model.lastReport {
                    StatCard(label: "Last clean",
                             value: ByteFormat.human(report.freedBytes),
                             detail: "moved to Trash")
                }
                StatCard(label: "Originals",
                         value: "Kept",
                         detail: "attachments stay with their messages")
                StatCard(label: "Safety",
                         value: "Trash-only",
                         detail: "everything is recoverable",
                         valueColor: Color(hex: 0x7BE8A8))
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 26)
            .padding(.bottom, 26)
        }
    }

    // MARK: - Scanning (live byte counter)

    private var scanningView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Mail Attachments") { StatusPill(text: "Scanning…", tone: .blue) }

            Spacer()

            Orb(size: 230, animating: true)
                .overlay(
                    VStack(spacing: 3) {
                        Text("COPIES FOUND")
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

            Text("Looking through Mail's download folders · \(model.foundCount) files found")
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(Palette.sub)
                .padding(.top, 16)

            GhostButton(title: "Stop") { model.stopScan() }
                .padding(.top, 24)

            Spacer()
        }
    }

    // MARK: - Cleaning

    private var cleaningView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Mail Attachments") { StatusPill(text: "Cleaning…", tone: .blue) }

            Spacer()

            Orb(size: 230, animating: true)

            Text("Moving to Trash…")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 6)

            Text("Moving \(model.selectedCount) files (\(ByteFormat.human(model.selectedBytes))) to Trash…")
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(Palette.sub)
                .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Done

    /// Items the last clean could not move — failed plus safety-blocked.
    private var skippedCount: Int {
        model.lastReport.map { $0.failed.count + $0.blocked.count } ?? 0
    }

    private var doneView: some View {
        let skipped = skippedCount
        var summary = "Freed \(ByteFormat.human(model.lastReport?.freedBytes ?? 0)) · moved \(model.lastReport?.trashed.count ?? 0) files to Trash"
        if skipped > 0 { summary += " · \(skipped) files could not be moved" }
        return VStack(spacing: 0) {
            TopBar(title: "Mail Attachments") {
                if skipped > 0 {
                    StatusPill(text: "\(skipped) skipped", tone: .warn)
                } else {
                    StatusPill(text: "All clean", tone: .good)
                }
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.45), radius: 18)

            Text(skipped > 0 ? "Cleaned with \(skipped) files skipped" : "All clean!")
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

    // MARK: - Results (flat list, largest first)

    private var resultsView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Mail Attachments") {
                if model.wasCancelled {
                    StatusPill(text: "Partial — scan stopped early", tone: .warn)
                } else {
                    StatusPill(text: "\(model.selectedCount) selected", tone: .blue)
                }
            }

            if model.attachments.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    summaryHeader
                    if model.accessDenied { accessBanner }
                    attachmentList
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 26)
                .padding(.top, 4)
                .padding(.bottom, 14)

                bottomBar
            }
        }
    }

    /// Hero total: what is currently selected, live — the same number the
    /// Clean button acts on.
    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ByteFormat.human(model.selectedBytes))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: model.selectedBytes)
            Text("selected in \(model.selectedCount) files · removed copies go to the Trash")
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(Palette.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attachmentList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                selectAllRow
                ForEach(model.attachments) { attachment in
                    MailAttachmentRow(
                        attachment: attachment,
                        selected: model.isSelected(attachment.id),
                        maxBytes: maxBytes,
                        onToggle: { model.toggle(attachment.id) }
                    )
                }
            }
            .padding(.bottom, 14)
        }
    }

    /// Biggest listed file — the shared denominator for every row's size bar.
    private var maxBytes: Int64 {
        model.attachments.first?.sizeBytes ?? 0
    }

    private var selectAllRow: some View {
        Button { model.toggleAll() } label: {
            HStack(spacing: 12) {
                GlassCheckbox(state: model.selectAllState) { model.toggleAll() }
                Text(model.allSelected ? "Deselect all" : "Select all")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.ink2)
                Spacer()
                Text("\(model.attachments.count) files · \(ByteFormat.human(model.totalBytes))")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)
            }
            .padding(.vertical, 9).padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(radius: 14)
    }

    private var bottomBar: some View {
        BottomBar {
            Text("\(model.selectedCount) of \(model.attachments.count) files · \(ByteFormat.human(model.selectedBytes)) selected")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.sub)

            Spacer()

            GhostButton(title: "Rescan") { model.startScan() }

            GradientButton(title: "Clean \(ByteFormat.human(model.selectedBytes))",
                           disabled: model.selectedCount == 0) { showConfirm = true }
        }
        .confirmationDialog(
            "Move \(model.selectedCount) files (\(ByteFormat.human(model.selectedBytes))) to the Trash?",
            isPresented: $showConfirm, titleVisibility: .visible
        ) {
            Button("Move to Trash") { Task { await model.clean() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These are Mail's local copies — the original attachments stay with their messages. Nothing is deleted permanently; everything can be restored from the Trash.")
        }
    }

    /// Slim warn strip shown when some results exist but a Mail folder could
    /// not be read (missing Full Disk Access).
    private var accessBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 11))
                .foregroundStyle(PillTone.warn.text)
            Text("One of Mail's download folders couldn't be read — grant Full Disk Access in System Settings for a complete scan.")
                .font(.caption)
                .foregroundStyle(Palette.ink2.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Button("Open System Settings") { openFullDiskAccessSettings() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PillTone.warn.text)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(PillTone.warn.fill))
    }

    // MARK: - Empty state (nothing found / access denied)

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            if model.accessDenied {
                Image(systemName: "lock.shield")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.5))
                Text("Mail's download folder can't be read")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("macOS protects Mail's data. Grant Full Disk Access in System Settings › Privacy & Security, then scan again.")
                    .font(.caption)
                    .foregroundStyle(Palette.sub)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                GhostButton(title: "Open System Settings") { openFullDiskAccessSettings() }
                    .padding(.top, 8)
                GhostButton(title: "Rescan") { model.startScan() }
            } else {
                Image(systemName: "envelope.open")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.5))
                Text("No attachment copies found")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Mail's download folders are already clean — nothing to reclaim here.")
                    .font(.caption)
                    .foregroundStyle(Palette.sub)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                GhostButton(title: "Rescan") { model.startScan() }
                    .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - One attachment row (its own glass card)

private struct MailAttachmentRow: View {
    let attachment: MailAttachment
    let selected: Bool
    /// Biggest listed file — denominator for the relative size bar.
    let maxBytes: Int64
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            GlassCheckbox(on: selected, action: onToggle)
                .accessibilityLabel(attachment.name)
                .accessibilityValue(selected ? "Selected for removal" : "Not selected")

            Image(systemName: "paperclip")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(attachment.path)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)
                    .lineLimit(1)
                    .truncationMode(.middle)
                RelativeSizeBar(value: attachment.sizeBytes, max: maxBytes)
                    .padding(.top, 3)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                SizeText(attachment.sizeBytes)
                if let date = attachment.modificationDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.tiny)
                }
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([attachment.url])
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
