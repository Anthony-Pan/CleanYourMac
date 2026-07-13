import SwiftUI

/// App sections shown in the sidebar.
enum AppSection: String, CaseIterable, Identifiable {
    case smartScan, systemJunk, uninstaller, largeFiles, privacy

    var id: String { rawValue }
    var title: String {
        switch self {
        case .smartScan: return "Smart Scan"
        case .systemJunk: return "System Junk"
        case .uninstaller: return "Uninstaller"
        case .largeFiles: return "Large & Old Files"
        case .privacy: return "Privacy"
        }
    }
    var symbol: String {
        switch self {
        case .smartScan: return "sparkles"
        case .systemJunk: return "internaldrive"
        case .uninstaller: return "trash"
        case .largeFiles: return "doc.viewfinder"
        case .privacy: return "hand.raised"
        }
    }
    /// The sidebar nav dot (mockup `.nid` gradients).
    var dotGradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .smartScan:   colors = [Color(hex: 0x6FD3FF), Color(hex: 0x8F5BFF)]
        case .systemJunk:  colors = [Color(hex: 0x6FA8FF), Color(hex: 0x3E62D9)]
        case .largeFiles:  colors = [Color(hex: 0x5BE0C8), Color(hex: 0x1FA88F)]
        case .privacy:     colors = [Color(hex: 0xFF8FD0), Color(hex: 0xC04AE0)]
        case .uninstaller: colors = [Color(hex: 0xFFC37B), Color(hex: 0xFF7A4D)]
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
                    case .uninstaller:
                        UninstallerView(model: uninstallModel)
                    case .largeFiles:
                        LargeFilesView(model: largeFilesModel)
                    case .privacy:
                        PrivacyView(model: privacyModel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1080, minHeight: 680)
        .preferredColorScheme(.dark)
    }
}
