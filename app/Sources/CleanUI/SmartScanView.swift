import SwiftUI
import CleanCore

/// The Smart Scan dashboard: one Scan runs every module concurrently, the
/// results screen shows one card per area, and each card opens its module
/// screen — already loaded, because the scans ran on the shared models.
/// Nothing is ever cleaned from here; removal lives in the module screens
/// with their own confirmations.
struct SmartScanView: View {
    let model: SmartScanViewModel
    @Binding var selection: AppSection
    @State private var volumeFree: Int64?
    @State private var volumeTotal: Int64?

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
        .navigationTitle("Smart Scan")
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Smart Scan") { StatusPill(text: "Ready", tone: .blue) }

            Spacer()

            Orb(size: 230)

            Text("One scan for your whole Mac")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 6)

            Text("Checks System Junk, Large & Old Files, Privacy and Applications together in a single pass.")
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
                StatCard(label: "Coverage",
                         value: "4 areas",
                         detail: "junk · files · privacy · apps")
                StatCard(label: "Safety",
                         value: "Review first",
                         detail: "cleaning stays in each area",
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

    // MARK: - Scanning

    private var scanningView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Smart Scan") { StatusPill(text: "Scanning…", tone: .blue) }

            Spacer()

            Orb(size: 230, animating: true)
                .overlay(
                    VStack(spacing: 3) {
                        Text("FOUND SO FAR")
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(1.3)
                            .foregroundStyle(Palette.slab)
                        Text(ByteFormat.human(model.foundBytes))
                            .font(.system(size: 32, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: model.foundBytes)
                    }
                )

            SweepBar(fraction: Double(model.doneCount) / Double(model.moduleCount))
                .padding(.top, 16)

            Text("\(model.doneCount) of \(model.moduleCount) areas complete")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Palette.tiny)
                .padding(.top, 10)

            VStack(spacing: 8) {
                ForEach(SmartScanViewModel.Module.allCases) { module in
                    moduleProgressRow(module)
                }
            }
            .frame(width: 460)
            .padding(.top, 22)

            GhostButton(title: "Stop") { model.stopScan() }
                .padding(.top, 24)

            Spacer()
        }
    }

    private func moduleProgressRow(_ module: SmartScanViewModel.Module) -> some View {
        let state = model.state(module)
        return HStack {
            Text(style(for: module).title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            switch state {
            case .done:
                Text("✓ \(doneSummary(module))")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: 0x7BE8A8))
            case .running:
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
        .glassCard(radius: 14, focused: state == .running)
        .opacity(state == .waiting ? 0.5 : 1)
    }

    private func doneSummary(_ module: SmartScanViewModel.Module) -> String {
        switch module {
        case .junk:       return ByteFormat.human(model.junkBytes)
        case .largeFiles: return ByteFormat.human(model.filesBytes)
        case .privacy:    return ByteFormat.human(model.privacyBytes)
        case .apps:       return "\(model.appCount) apps"
        }
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Smart Scan") {
                if model.wasCancelled {
                    StatusPill(text: "Partial — scan stopped early", tone: .warn)
                } else {
                    StatusPill(text: "\(ByteFormat.human(model.foundBytes)) found", tone: .blue)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                summaryHeader

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                    GridItem(.flexible(), spacing: 14)],
                          spacing: 14) {
                    ForEach(SmartScanViewModel.Module.allCases) { module in
                        ModuleCard(style: style(for: module),
                                   value: cardValue(module),
                                   detail: cardDetail(module),
                                   pendingDetail: cardDetailPending(module)) {
                            withAnimation(.snappy(duration: 0.2)) {
                                selection = style(for: module).section
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 26)
            .padding(.top, 4)
            .padding(.bottom, 14)

            BottomBar {
                Text("\(model.doneCount) of \(model.moduleCount) areas scanned · \(ByteFormat.human(model.foundBytes)) found")
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(Palette.sub)

                Spacer()

                GhostButton(title: "Rescan") { model.startScan() }
            }
        }
    }

    /// Hero: everything the scan found across the reviewable areas. "All
    /// clear" replaces a fake-looking zero byte count.
    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.foundBytes > 0 {
                Text(ByteFormat.human(model.foundBytes))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("found across junk, large files and privacy · open an area to review and clean")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.sub)
            } else {
                Text("All clear")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                Text("no junk, oversized files or privacy traces found")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.sub)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cardValue(_ module: SmartScanViewModel.Module) -> String {
        switch module {
        case .junk:
            return model.junkBytes > 0 ? ByteFormat.human(model.junkBytes) : "All clear"
        case .largeFiles:
            return model.filesBytes > 0 ? ByteFormat.human(model.filesBytes) : "All clear"
        case .privacy:
            return model.privacyBytes > 0 ? ByteFormat.human(model.privacyBytes) : "All clear"
        case .apps:
            return "\(model.appCount) apps"
        }
    }

    /// Sub-line under the card value. Returns nil when the number it needs is
    /// still being computed — the card shows a shimmer instead.
    private func cardDetail(_ module: SmartScanViewModel.Module) -> String? {
        switch module {
        case .junk:
            return model.junkBytes > 0
                ? "\(model.junkItemCount) items · safe items pre-selected"
                : "no junk in the scanned locations"
        case .largeFiles:
            return model.filesBytes > 0
                ? "\(model.filesCount) files to review in your folders"
                : "no files over the size threshold"
        case .privacy:
            let issues = model.privacyFindingCount
            return model.privacyBytes > 0
                ? "\(model.privacyTraceCount) traces · \(issues == 0 ? "no issues found" : "\(issues) potential issues")"
                : (issues == 0 ? "no traces or issues found" : "\(issues) potential issues to review")
        case .apps:
            guard let bytes = model.appsSizedBytes else { return nil }
            return "\(ByteFormat.human(bytes)) on disk · review in Uninstaller"
        }
    }

    /// True while the module's detail line is waiting on real data.
    private func cardDetailPending(_ module: SmartScanViewModel.Module) -> Bool {
        module == .apps && model.appsSizedBytes == nil
    }
}

// MARK: - Module display metadata

/// Each dashboard area's fixed presentation: the module title, icon and the
/// same gradient its sidebar dot uses, plus the section a card opens.
private struct ModuleStyle {
    let title: String
    let symbol: String
    let colors: [Color]
    let section: AppSection

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private func style(for module: SmartScanViewModel.Module) -> ModuleStyle {
    switch module {
    case .junk:
        return ModuleStyle(title: "System Junk", symbol: "internaldrive.fill",
                           colors: [Color(hex: 0x6FA8FF), Color(hex: 0x3E62D9)],
                           section: .systemJunk)
    case .largeFiles:
        return ModuleStyle(title: "Large & Old Files", symbol: "doc.viewfinder.fill",
                           colors: [Color(hex: 0x5BE0C8), Color(hex: 0x1FA88F)],
                           section: .largeFiles)
    case .privacy:
        return ModuleStyle(title: "Privacy", symbol: "hand.raised.fill",
                           colors: [Color(hex: 0xFF8FD0), Color(hex: 0xC04AE0)],
                           section: .privacy)
    case .apps:
        return ModuleStyle(title: "Applications", symbol: "trash.fill",
                           colors: [Color(hex: 0xFFC37B), Color(hex: 0xFF7A4D)],
                           section: .uninstaller)
    }
}

// MARK: - Module card

/// One dashboard card per area: icon tile, name, headline number, sub-line.
/// The whole card is a button that opens the module screen.
private struct ModuleCard: View {
    let style: ModuleStyle
    let value: String
    let detail: String?
    let pendingDetail: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(style.gradient)
                        .frame(width: 32, height: 32)
                        .overlay(Image(systemName: style.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white))

                    Text(style.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.tiny)
                }

                Text(value)
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tiny)
                        .lineLimit(1)
                } else if pendingDetail {
                    SizePending()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 16, focused: hover)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel("\(style.title): \(value). Open \(style.title).")
    }
}
