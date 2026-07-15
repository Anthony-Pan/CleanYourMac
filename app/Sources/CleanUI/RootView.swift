import SwiftUI

/// App sections shown in the sidebar.
enum AppSection: String, CaseIterable, Identifiable {
    case smartScan
    case systemJunk, mailAttachments, trashBins
    case optimization, maintenance
    case privacy
    case uninstaller
    case largeFiles, spaceLens

    var id: String { rawValue }
    var title: String {
        switch self {
        case .smartScan: return "Smart Scan"
        case .systemJunk: return "System Junk"
        case .mailAttachments: return "Mail Attachments"
        case .trashBins: return "Trash Bins"
        case .optimization: return "Optimization"
        case .maintenance: return "Maintenance"
        case .privacy: return "Privacy"
        case .uninstaller: return "Uninstaller"
        case .largeFiles: return "Large & Old Files"
        case .spaceLens: return "Space Lens"
        }
    }
    var symbol: String {
        switch self {
        case .smartScan: return "sparkles"
        case .systemJunk: return "internaldrive"
        case .mailAttachments: return "paperclip"
        case .trashBins: return "trash"
        case .optimization: return "speedometer"
        case .maintenance: return "wrench.and.screwdriver"
        case .privacy: return "hand.raised"
        case .uninstaller: return "xmark.bin"
        case .largeFiles: return "doc.viewfinder"
        case .spaceLens: return "chart.pie"
        }
    }
    /// The sidebar icon-tile gradient (Onyx-harmonized, muted — never neon).
    var dotGradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .smartScan:       colors = [Color(hex: 0xD8C49A), Color(hex: 0xB79E72)] // champagne
        case .systemJunk:      colors = [Color(hex: 0xC7B48D), Color(hex: 0x998459)] // dune
        case .mailAttachments: colors = [Color(hex: 0x93A9BC), Color(hex: 0x64809A)] // steel blue
        case .trashBins:       colors = [Color(hex: 0xABA59D), Color(hex: 0x7C766E)] // warm grey
        case .optimization:    colors = [Color(hex: 0xAEB48D), Color(hex: 0x7F865E)] // olive
        case .maintenance:     colors = [Color(hex: 0xC9906B), Color(hex: 0x9B6845)] // copper
        case .privacy:         colors = [Color(hex: 0xC79191), Color(hex: 0x9E6767)] // warm rose
        case .uninstaller:     colors = [Color(hex: 0xD4A66A), Color(hex: 0xB07C3A)] // amber
        case .largeFiles:      colors = [Color(hex: 0x8FB0A0), Color(hex: 0x5C8375)] // muted teal
        case .spaceLens:       colors = [Color(hex: 0x9AA5B8), Color(hex: 0x6B7890)] // slate
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Top-level shell: the aurora stage behind a labeled glass sidebar and the
/// active section. Privacy warms the aurora; everything else shares one stage.
public struct RootView: View {
    @State private var selection: AppSection = .smartScan
    // Owned here so their state (scan results, discovered apps) survives sidebar
    // switches instead of being thrown away each time the view is recreated.
    @State private var scanModel: ScanViewModel
    @State private var uninstallModel: UninstallViewModel
    @State private var largeFilesModel: LargeFilesViewModel
    @State private var privacyModel: PrivacyViewModel
    // Smart Scan orchestrates the four module models above, so opening a
    // module after a Smart Scan lands on its fully loaded screen.
    @State private var smartModel: SmartScanViewModel
    @State private var mailModel: MailAttachmentsViewModel
    @State private var trashModel: TrashBinsViewModel
    @State private var optimizationModel: OptimizationViewModel
    @State private var maintenanceModel: MaintenanceViewModel
    @State private var spaceLensModel: SpaceLensViewModel

    public init() {
        let junk = ScanViewModel()
        let apps = UninstallViewModel()
        let files = LargeFilesViewModel()
        let privacy = PrivacyViewModel()
        _scanModel = State(initialValue: junk)
        _uninstallModel = State(initialValue: apps)
        _largeFilesModel = State(initialValue: files)
        _privacyModel = State(initialValue: privacy)
        _smartModel = State(initialValue: SmartScanViewModel(
            junk: junk, files: files, privacy: privacy, apps: apps))
        _mailModel = State(initialValue: MailAttachmentsViewModel())
        _trashModel = State(initialValue: TrashBinsViewModel())
        _optimizationModel = State(initialValue: OptimizationViewModel())
        _maintenanceModel = State(initialValue: MaintenanceViewModel())
        _spaceLensModel = State(initialValue: SpaceLensViewModel())
    }

    public var body: some View {
        ZStack {
            AuroraBackground(variant: selection == .privacy ? .privacy : .standard)
                .animation(.easeInOut(duration: 0.35), value: selection == .privacy)

            HStack(spacing: 0) {
                Sidebar(selection: $selection)

                ZStack {
                    switch selection {
                    case .smartScan:
                        SmartScanView(model: smartModel, selection: $selection)
                    case .systemJunk:
                        SystemJunkView(model: scanModel)
                    case .mailAttachments:
                        MailAttachmentsView(model: mailModel)
                    case .trashBins:
                        TrashBinsView(model: trashModel)
                    case .optimization:
                        OptimizationView(model: optimizationModel)
                    case .maintenance:
                        MaintenanceView(model: maintenanceModel)
                    case .uninstaller:
                        UninstallerView(model: uninstallModel)
                    case .largeFiles:
                        LargeFilesView(model: largeFilesModel)
                    case .spaceLens:
                        SpaceLensView(model: spaceLensModel)
                    case .privacy:
                        PrivacyView(model: privacyModel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1120, minHeight: 740)
        .preferredColorScheme(.dark)
    }
}
