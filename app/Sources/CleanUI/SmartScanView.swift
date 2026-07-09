import SwiftUI
import AppKit
import CleanCore

struct SmartScanView: View {
    let model: ScanViewModel
    @State private var showConfirm = false
    @State private var volumeFree: Int64?
    @State private var volumeTotal: Int64?
    /// Folder name → resolved app display name (nil = looked up, no match).
    @State private var displayNameCache: [String: String?] = [:]

    init(model: ScanViewModel) { self.model = model }

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
        .navigationTitle("Smart Scan")
    }

    // MARK: - Idle (start screen with a Scan button)

    private var idleView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Smart Scan") { StatusPill(text: "Ready", tone: .blue) }

            Spacer()

            Orb(size: 230)

            Text("Your Mac is ready for a checkup")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 6)

            Text("Find caches, logs and developer junk you can safely reclaim.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.sub)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 8)

            CTACircle(title: "Scan") { model.startScan() }
                .padding(.top, 30)

            Spacer()

            HStack(spacing: 14) {
                if let free = volumeFree {
                    StatCard(label: "Free space",
                             value: ByteFormat.human(free),
                             detail: volumeTotal.map { "of \(ByteFormat.human($0))" } ?? "")
                }
                if let report = model.lastReport {
                    StatCard(label: "Last clean",
                             value: ByteFormat.human(report.freedBytes),
                             detail: "moved to Trash")
                }
                StatCard(label: "Safety",
                         value: "Trash-only",
                         detail: "everything is recoverable",
                         valueColor: Color(hex: 0x7BE8A8))
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 26)
            .padding(.bottom, 26)
        }
        .onAppear { refreshVolumeStats() }
    }

    private func refreshVolumeStats() {
        let values = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        volumeFree = values?.volumeAvailableCapacityForImportantUsage
        volumeTotal = (values?.volumeTotalCapacity).map(Int64.init)
    }

    // MARK: - Scanning (live discovery)

    private var scanningView: some View {
        let doneCount = model.categoryProgress.filter { $0.state == .done }.count
        let totalCount = model.categoryProgress.count
        return VStack(spacing: 0) {
            TopBar(title: "Smart Scan") { StatusPill(text: "Scanning…", tone: .blue) }

            Spacer()

            Orb(size: 230, animating: true)
                .overlay(
                    VStack(spacing: 3) {
                        Text("JUNK FOUND")
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

            SweepBar(fraction: totalCount > 0 ? Double(doneCount) / Double(totalCount) : 0)
                .padding(.top, 16)

            Text(model.currentLocation.isEmpty
                 ? "Scanning… · \(model.foundCount) items found"
                 : "Scanning \(model.currentLocation) · \(model.foundCount) items found")
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(Palette.sub)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 380)
                .padding(.top, 10)

            Text("Step \(min(doneCount + 1, totalCount)) of \(totalCount) locations")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Palette.tiny)
                .padding(.top, 4)

            VStack(spacing: 8) {
                ForEach(model.categoryProgress, id: \.id) { row in
                    categoryProgressRow(row)
                }
            }
            .frame(width: 460)
            .padding(.top, 22)

            GhostButton(title: "Stop") { model.cancelScan() }
                .padding(.top, 24)

            Spacer()
        }
    }

    private func categoryProgressRow(
        _ row: (id: String, name: String, state: CategoryScanState, bytes: Int64)
    ) -> some View {
        HStack {
            Text(row.name)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            switch row.state {
            case .done:
                Text("✓ \(ByteFormat.human(row.bytes))")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: 0x7BE8A8))
            case .active:
                Text("scanning…")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)
            case .waiting:
                Text("—")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.sub)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCard(radius: 14, focused: row.state == .active)
        .opacity(row.state == .waiting ? 0.5 : 1)
    }

    // MARK: - Cleaning

    private var cleaningView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Smart Scan") { StatusPill(text: "Cleaning…", tone: .blue) }

            Spacer()

            Orb(size: 230, animating: true)

            Text("Moving to Trash…")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 6)

            Text("Moving \(model.selectedItemCount) items (\(ByteFormat.human(model.selectedBytes))) to Trash…")
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

    /// Items the last clean could not move — failed plus safety-blocked.
    private var skippedCount: Int {
        model.lastReport.map { $0.failed.count + $0.blocked.count } ?? 0
    }

    private var doneView: some View {
        let skipped = skippedCount
        var summary = "Freed \(ByteFormat.human(model.lastReport?.freedBytes ?? 0)) · moved \(model.lastReport?.trashed.count ?? 0) items to Trash"
        if skipped > 0 { summary += " · \(skipped) items could not be moved" }
        return VStack(spacing: 0) {
            TopBar(title: "Smart Scan") {
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

            Text(skipped > 0 ? "Cleaned with \(skipped) items skipped" : "All clean!")
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

    // MARK: - Results (category rows + inspector split)

    private var resultsView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Smart Scan") {
                if model.wasCancelled {
                    StatusPill(text: "Partial — scan stopped early", tone: .warn)
                } else {
                    StatusPill(text: "\(model.selectedItemCount) selected", tone: .blue)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    summaryHeader

                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(sortedGroups) { group in
                                categoryRow(group)
                            }
                        }
                        .padding(.bottom, 14)
                    }

                    breakdownCard
                }

                inspectorPanel
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 26)
            .padding(.top, 4)
            .padding(.bottom, 14)

            BottomBar {
                Text("\(selectedCategoryCount) of \(model.groups.count) categories · \(ByteFormat.human(model.selectedBytes)) selected")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.sub)

                Spacer()

                if model.wasCancelled {
                    GhostButton(title: "Finish scan") { model.startScan() }
                }

                GhostButton(title: "Rescan") { model.startScan() }

                GradientButton(title: "Clean \(ByteFormat.human(model.selectedBytes))",
                               disabled: model.selectedItemCount == 0) { showConfirm = true }
            }
        }
        .onAppear {
            if model.openedCategoryID == nil {
                model.openedCategoryID = sortedGroups.first?.id
            }
        }
        .confirmationDialog(
            "Move \(model.selectedItemCount) items (\(ByteFormat.human(model.selectedBytes))) to the Trash?",
            isPresented: $showConfirm, titleVisibility: .visible
        ) {
            Button("Move to Trash") { Task { await model.clean() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing is deleted permanently — you can restore everything from the Trash.")
        }
    }

    private var selectedCategoryCount: Int {
        model.groups.filter { model.categoryState($0) != .none }.count
    }

    /// Categories biggest-first — the order of the list, legend and bar.
    private var sortedGroups: [ScanResultGroup] {
        model.groups.sorted { $0.totalBytes > $1.totalBytes }
    }

    private var totalFoundBytes: Int64 {
        model.groups.reduce(0) { $0 + $1.totalBytes }
    }

    private var inspectedGroup: ScanResultGroup? {
        guard let id = model.openedCategoryID else { return sortedGroups.first }
        return model.groups.first { $0.id == id } ?? sortedGroups.first
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
            Text("selected in \(model.selectedItemCount) items · removed items go to the Trash")
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(Palette.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Stacked proportion bar + legend: how the found junk divides across
    /// categories. Real bytes only; hidden when nothing was found.
    @ViewBuilder private var breakdownCard: some View {
        let groups = sortedGroups
        let total = totalFoundBytes
        if total > 0 {
            VStack(alignment: .leading, spacing: 10) {
                Text("Space breakdown")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.ink2)

                GeometryReader { geo in
                    let gaps = CGFloat(max(0, groups.count - 1)) * 2
                    HStack(spacing: 2) {
                        ForEach(groups) { group in
                            Capsule()
                                .fill(CategoryStyle.forID(group.category.id).gradient)
                                .frame(width: max(2, (geo.size.width - gaps)
                                    * CGFloat(group.totalBytes) / CGFloat(total)))
                        }
                    }
                }
                .frame(height: 10)

                ForEach(groups) { group in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(CategoryStyle.forID(group.category.id).gradient)
                            .frame(width: 8, height: 8)
                        Text(group.category.nameEN)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.sub)
                        Spacer()
                        SizeText(group.totalBytes)
                    }
                }
            }
            .padding(16)
            .glassCard(radius: 16)
        }
    }

    private func categoryRow(_ group: ScanResultGroup) -> some View {
        let style = CategoryStyle.forID(group.category.id)
        let state = model.checkState(group)
        return HStack(spacing: 12) {
            GlassCheckbox(state: state) {
                model.toggleCategory(group)
            }

            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(style.gradient)
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: style.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white))

            VStack(alignment: .leading, spacing: 4) {
                Text(group.category.nameEN)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                RelativeSizeBar(value: group.totalBytes,
                                max: sortedGroups.first?.totalBytes ?? 0,
                                gradient: style.gradient)
                Text(state == .mixed
                     ? "\(model.selectedCount(in: group)) of \(group.items.count) selected"
                     : "\(group.items.count) items · \(group.category.detailEN)")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)
                    .lineLimit(1)
            }

            Spacer()

            SizeText(group.totalBytes, emphasized: group.id == sortedGroups.first?.id)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .glassCard(radius: 14, focused: model.openedCategoryID == group.id)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { model.openedCategoryID = group.id }
    }

    // MARK: Inspector panel (right column)

    @ViewBuilder private var inspectorPanel: some View {
        if let group = inspectedGroup {
            VStack(alignment: .leading, spacing: 0) {
                Text(group.category.nameEN)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Text(group.category.detailEN)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.sub)
                    .padding(.top, 3)

                Text("\(model.selectedCount(in: group)) of \(group.items.count) selected · \(ByteFormat.human(group.totalBytes))")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.sub)
                    .padding(.top, 3)

                Button { model.toggleCategory(group) } label: {
                    Text(model.categoryState(group) == .all ? "Deselect all" : "Select all")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(0.10))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(.white.opacity(0.16), lineWidth: 1))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(group.items) { item in
                            inspectorItemRow(item)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .padding(.top, 12)

                Text("Removed items go to the Trash — recoverable.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(width: 320)
            .frame(maxHeight: .infinity, alignment: .top)
            .glassCard(radius: 16)
        }
    }

    /// Friendly names for bundle-id-style cache folders (e.g.
    /// "com.apple.Safari" → "Safari"). Real lookups only — a folder that
    /// doesn't resolve to an installed app keeps its raw name. Memoized so
    /// NSWorkspace isn't queried on every render; `.some(nil)` records a miss.
    private func friendlyName(for folder: String) -> String? {
        displayNameCache[folder] ?? nil
    }

    private func resolveFriendlyName(_ folder: String) {
        guard displayNameCache[folder] == nil else { return }
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: folder)
        displayNameCache[folder] = appURL.map { FileManager.default.displayName(atPath: $0.path) }
    }

    private func inspectorItemRow(_ item: ScanItem) -> some View {
        let folder = item.url.lastPathComponent
        let display = friendlyName(for: folder)
        return HStack(spacing: 9) {
            GlassCheckbox(on: model.isItemSelected(item.id)) {
                model.toggleItem(item.id)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(display ?? folder)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Text(display != nil ? folder : item.path)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            SizeText(item.sizeBytes)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.sub)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 7)
        .onAppear { resolveFriendlyName(folder) }
    }
}

// MARK: - Sweep progress bar (scanning + cleaning screens)

/// Progress capsule: determinate when `fraction` is given (fill grows with
/// progress, shimmer sweeps inside the filled portion only), indeterminate
/// otherwise (the original travelling gradient).
private struct SweepBar: View {
    var fraction: Double? = nil

    @State private var sweep = false

    private static let width: CGFloat = 280
    private static let gradient = LinearGradient(
        colors: [Color(hex: 0x6FD3FF), Color(hex: 0xB06CFF)],
        startPoint: .leading, endPoint: .trailing)

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.12))

            if let fraction {
                Capsule()
                    .fill(Self.gradient)
                    .frame(width: Self.width * min(1, max(0, fraction)), height: 6)
                    .overlay(
                        Capsule()
                            .fill(.white.opacity(0.35))
                            .frame(width: 40, height: 6)
                            .offset(x: sweep ? Self.width : -40)
                    )
                    .clipShape(Capsule())
                    .animation(.snappy, value: fraction)
            } else {
                Capsule()
                    .fill(Self.gradient)
                    .frame(width: 90, height: 6)
                    .offset(x: sweep ? Self.width : -90)
            }
        }
        .frame(width: Self.width, height: 6)
        .clipShape(Capsule())
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                sweep = true
            }
        }
        .accessibilityHidden(true)
    }
}
