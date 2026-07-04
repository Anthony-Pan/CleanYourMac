import SwiftUI
import AppKit
import QuickLook
import CleanCore

/// The Large & Old Files screen: find the biggest, least-used files in the
/// user's content folders (plus any folders they add) and move the ones they
/// pick to the Trash. Nothing is ever selected automatically — these are the
/// user's own documents.
struct LargeFilesView: View {
    @Bindable var model: LargeFilesViewModel
    @State private var showConfirm = false
    /// Drives the system Quick Look panel (space-bar style preview).
    @State private var previewURL: URL?

    init(model: LargeFilesViewModel) { self.model = model }

    var body: some View {
        Group {
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
        .alert("Can’t add that folder", isPresented: locationErrorShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.locationError ?? "")
        }
    }

    private var locationErrorShown: Binding<Bool> {
        Binding(
            get: { model.locationError != nil },
            set: { if !$0 { model.locationError = nil } }
        )
    }

    // MARK: - Busy (scanning is cancellable; cleaning is not)

    private var busyView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Large & Old Files") {
                StatusPill(text: model.phase == .cleaning ? "Cleaning…" : "Scanning…", tone: .blue)
            }

            Spacer()

            Orb(size: 230, animating: true)

            Text(model.phase == .cleaning ? "Moving to Trash…" : "Digging through your files…")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 24)

            if model.phase != .cleaning, model.progressScanned > 0 {
                Text("Checked \(model.progressScanned) files · found \(model.progressFound) large ones")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.sub)
                    .monospacedDigit()
                    .padding(.top, 8)
            }

            if model.phase != .cleaning {
                // Stopping keeps everything found so far — partial results, not
                // a blank screen.
                GhostButton(title: "Stop") { model.stopScan() }
                    .padding(.top, 26)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Large & Old Files") {
                StatusPill(text: "Done", tone: .good)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)

            Text("Done!")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 16)

            Text("Freed \(ByteFormat.human(model.lastReport?.freedBytes ?? 0)) · moved \(model.lastReport?.trashed.count ?? 0) files to Trash")
                .font(.system(size: 13))
                .foregroundStyle(Palette.sub)
                .padding(.top, 6)

            if let report = model.lastReport, !report.failed.isEmpty || !report.blocked.isEmpty {
                Text("\(report.failed.count + report.blocked.count) file(s) couldn’t be moved and were left untouched.")
                    .font(.caption)
                    .foregroundStyle(PillTone.warn.text)
                    .padding(.top, 4)
            }

            CTACircle(title: "Scan Again") { Task { await model.scan() } }
                .padding(.top, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Large & Old Files") {
                StatusPill(text: "\(model.visibleFiles.count) files · \(ByteFormat.human(model.visibleBytes))",
                           tone: .blue)
            }

            Text(headerSubtitle)
                .font(.system(size: 12))
                .foregroundStyle(Palette.sub)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 26)
                .padding(.bottom, 10)

            filterBar
            safetyBanner

            if model.visibleFiles.isEmpty {
                emptyState
            } else {
                fileList
                bottomBar
            }
        }
    }

    private var headerSubtitle: String {
        let base = "Your biggest files across Downloads, Documents, Desktop, Movies, Music and Pictures"
        let extras = model.customRoots.count
        if extras == 0 { return base + "." }
        return base + " plus \(extras) folder\(extras == 1 ? "" : "s") you added."
    }

    /// Two scrollable control rows: primary filters on top; search, view and
    /// location tools below. Split so nothing clips at the 920 pt minimum width.
    private var filterBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    SegmentedPicker(selection: $model.sizeFilter,
                                    options: LargeFilesViewModel.SizeFilter.allCases,
                                    label: \.label)
                    SegmentedPicker(selection: $model.ageFilter,
                                    options: LargeFilesViewModel.AgeFilter.allCases,
                                    label: \.label)
                }
                .padding(.horizontal, 26)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    searchField
                    typeMenu
                    sortMenu
                    groupingMenu
                    locationsMenu
                    if model.ignoredCount > 0 { ignoredPill }
                    rescanPill
                }
                .padding(.horizontal, 26)
            }
        }
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Palette.sub)
            TextField("Search files", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .frame(width: 150)
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.sub)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.glassFill))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Palette.glassBorder, lineWidth: 1))
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

    private var groupingMenu: some View {
        Menu {
            ForEach(LargeFilesViewModel.Grouping.allCases) { grouping in
                Button {
                    model.grouping = grouping
                } label: {
                    Label(grouping.label, systemImage: model.grouping == grouping ? "checkmark" : "")
                }
            }
        } label: {
            pillLabel(systemImage: "rectangle.grid.1x2",
                      text: model.grouping == .kind ? "By kind" : "Flat list")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var locationsMenu: some View {
        Menu {
            Section("Always scanned") {
                Text("Downloads, Documents, Desktop, Movies, Music, Pictures")
            }
            if !model.customRoots.isEmpty {
                Section("Added by you — click to remove") {
                    ForEach(model.customRoots, id: \.path) { root in
                        Button("Remove “\(root.lastPathComponent)”") {
                            model.removeCustomRoot(root)
                        }
                    }
                }
            }
            Divider()
            Button("Add Folder…") { pickFolder() }
        } label: {
            pillLabel(systemImage: "folder",
                      text: model.customRoots.isEmpty
                          ? "Locations"
                          : "Locations +\(model.customRoots.count)")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// Ignored files are only hidden from the list — never touched on disk.
    private var ignoredPill: some View {
        Menu {
            Text("Ignored files are hidden from results, never touched.")
            Button("Show them again") { model.clearIgnoreList() }
        } label: {
            pillLabel(systemImage: "eye.slash", text: "\(model.ignoredCount) ignored")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var rescanPill: some View {
        Button { Task { await model.scan() } } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                Text("Rescan").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.glassFill))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Palette.glassBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a folder to include in the Large & Old Files scan."
        if panel.runModal() == .OK, let url = panel.url {
            model.addCustomRoot(url)
        }
    }

    private func pillLabel(systemImage: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 12))
            Text(text).font(.system(size: 12, weight: .medium))
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.glassFill))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Palette.glassBorder, lineWidth: 1))
    }

    private var safetyBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 12))
                .foregroundStyle(PillTone.warn.text)
            Text("These are your personal files. Nothing is selected for you — review each one. Removed files go to the Trash and can be restored.")
                .font(.caption)
                .foregroundStyle(Palette.ink2.opacity(0.9))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PillTone.warn.fill))
        .glassCard(radius: 10)
        .padding(.horizontal, 26)
        .padding(.bottom, 10)
    }

    // MARK: - File list (flat or grouped by kind; each row its own glass card)

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                selectAllRow

                if model.grouping == .kind {
                    ForEach(model.sections, id: \.kind) { section in
                        sectionHeader(section.kind, files: section.files)
                        rows(section.files)
                    }
                } else {
                    rows(model.visibleFiles)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 2)
            .padding(.bottom, 16)
        }
        .quickLookPreview($previewURL)
    }

    private func sectionHeader(_ kind: FileKind, files: [LargeFile]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: kind.symbol)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20)
            Text(kind.titleEN)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.ink2)
            Spacer()
            Text("\(files.count) files · \(ByteFormat.human(files.reduce(0) { $0 + $1.sizeBytes }))")
                .font(.system(size: 11))
                .foregroundStyle(Palette.tiny)
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func rows(_ files: [LargeFile]) -> some View {
        ForEach(files) { file in
            LargeFileRow(file: file,
                         selected: model.isSelected(file.id),
                         now: Date(),
                         onToggle: { model.toggle(file.id) },
                         onPreview: { previewURL = file.url },
                         onIgnore: { model.ignore(file) })
        }
    }

    private var selectAllRow: some View {
        Button { model.toggleAllVisible() } label: {
            HStack(spacing: 12) {
                GlassCheckbox(on: model.allVisibleSelected) { model.toggleAllVisible() }
                Text(model.allVisibleSelected ? "Deselect all shown" : "Select all shown")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.ink2)
                Spacer()
                Text("\(model.visibleFiles.count) files")
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
            Text("\(model.selectedCount) files · \(ByteFormat.human(model.selectedBytes)) selected")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.sub)

            Spacer()

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
            Text("These are your personal files. Nothing is deleted permanently — you can restore everything from the Trash.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 40)).foregroundStyle(.white.opacity(0.5))
            Text(model.searchText.isEmpty ? "No files match these filters." : "No files match your search.")
                .foregroundStyle(.white)
            Text("Try a smaller size or a wider age range.")
                .font(.caption).foregroundStyle(Palette.sub)
            Text("Files synced to iCloud Drive are skipped for safety, and macOS may ask for permission before Desktop & Documents can be read.")
                .font(.caption2)
                .foregroundStyle(Palette.tiny)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
    }
}

// MARK: - Segmented pill picker (mockup `.tabs`, replaces system Picker chrome)

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
                        .font(.system(size: 12, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.white : Color.white.opacity(0.6))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(on ? Color.white.opacity(0.16) : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.glassFill))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Palette.glassBorder, lineWidth: 1))
    }
}

// MARK: - One file row (its own glass card, mockup `.row`)

private struct LargeFileRow: View {
    let file: LargeFile
    let selected: Bool
    let now: Date
    let onToggle: () -> Void
    let onPreview: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            GlassCheckbox(on: selected, action: onToggle)
                .accessibilityLabel(file.name)
                .accessibilityValue(selected ? "Selected for removal" : "Not selected")

            Image(systemName: file.kind.symbol)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(file.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let age = ageBadge {
                        TagBadge(text: age, color: PillTone.warn.text)
                    }
                }
                Text(file.path)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormat.human(file.sizeBytes))
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(Palette.sub)
                if let usage = usageCaption {
                    Text(usage)
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.tiny)
                }
            }

            Button(action: onPreview) {
                Image(systemName: "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.sub)
            }
            .buttonStyle(.plain)
            .help("Quick Look")

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
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
        .contextMenu {
            Button("Quick Look", action: onPreview)
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            }
            Divider()
            // Ignoring only hides the file from results — it is never touched.
            Button("Ignore This File", action: onIgnore)
        }
    }

    /// Show an age chip only for genuinely unused files ("2y", "8mo", "180d"),
    /// judged by the later of modified/opened.
    private var ageBadge: String? {
        guard let days = file.ageDays(now: now), days >= 180 else { return nil }
        if days >= 365 { return "\(days / 365)y" }
        return "\(days / 30)mo"
    }

    /// A short honest caption of when the file was last modified or opened.
    private var usageCaption: String? {
        guard let days = file.ageDays(now: now) else { return nil }
        if days == 0 { return "Used today" }
        if days < 30 { return "Used \(days)d ago" }
        if days < 365 { return "Unused \(days / 30)mo" }
        return "Unused \(days / 365)y"
    }
}
