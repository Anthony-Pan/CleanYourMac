import SwiftUI
import AppKit
import CleanCore

struct SmartScanView: View {
    let model: ScanViewModel
    @State private var showConfirm = false
    @State private var volumeFree: Int64?
    @State private var volumeTotal: Int64?

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
        VStack(spacing: 0) {
            TopBar(title: "Smart Scan") { StatusPill(text: "Scanning…", tone: .blue) }

            Spacer()

            Orb(size: 230, animating: true)
                .overlay(
                    VStack(spacing: 3) {
                        Text(ByteFormat.human(model.scannedBytes))
                            .font(.system(size: 32, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: model.scannedBytes)
                        Text(model.currentLocation.isEmpty
                             ? "Scanning…"
                             : "Scanning \(model.currentLocation)…")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 150)
                    }
                )

            SweepBar()
                .padding(.top, 16)

            Text("\(model.foundCount) items found")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Palette.tiny)
                .padding(.top, 8)

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

            Spacer()
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Smart Scan") { StatusPill(text: "All clean", tone: .good) }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.45), radius: 18)

            Text("All clean!")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 18)

            Text("Freed \(ByteFormat.human(model.lastReport?.freedBytes ?? 0)) · moved \(model.lastReport?.trashed.count ?? 0) items to Trash")
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
                StatusPill(text: "\(model.selectedItemCount) items · \(ByteFormat.human(model.selectedBytes))",
                           tone: .warn)
            }

            HStack(alignment: .top, spacing: 14) {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.groups) { group in
                            categoryRow(group)
                        }
                    }
                    .padding(.bottom, 14)
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

                GhostButton(title: "Rescan") { model.startScan() }

                GradientButton(title: "Clean \(ByteFormat.human(model.selectedBytes))",
                               disabled: model.selectedItemCount == 0) { showConfirm = true }
            }
        }
        .onAppear {
            if model.openedCategoryID == nil {
                model.openedCategoryID = model.groups.first?.id
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

    private var inspectedGroup: ScanResultGroup? {
        guard let id = model.openedCategoryID else { return model.groups.first }
        return model.groups.first { $0.id == id } ?? model.groups.first
    }

    private func categoryRow(_ group: ScanResultGroup) -> some View {
        let style = CategoryStyle.forID(group.category.id)
        return HStack(spacing: 12) {
            GlassCheckbox(on: model.categoryState(group) != .none) {
                model.toggleCategory(group)
            }

            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(style.gradient)
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: style.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white))

            VStack(alignment: .leading, spacing: 2) {
                Text(group.category.nameEN)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(group.items.count) items")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)
            }

            Spacer()

            Text(ByteFormat.human(group.totalBytes))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Palette.sub)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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

    private func inspectorItemRow(_ item: ScanItem) -> some View {
        HStack(spacing: 9) {
            GlassCheckbox(on: model.isItemSelected(item.id)) {
                model.toggleItem(item.id)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Text(item.path)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(ByteFormat.human(item.sizeBytes))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Palette.sub)

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
    }
}

// MARK: - Indeterminate sweep progress bar (scanning screen)

private struct SweepBar: View {
    @State private var sweep = false

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.12))

            Capsule()
                .fill(LinearGradient(colors: [Color(hex: 0x6FD3FF), Color(hex: 0xB06CFF)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 90, height: 6)
                .offset(x: sweep ? 280 : -90)
        }
        .frame(width: 280, height: 6)
        .clipShape(Capsule())
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                sweep = true
            }
        }
        .accessibilityHidden(true)
    }
}
