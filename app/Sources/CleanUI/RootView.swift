import SwiftUI

/// App sections shown in the sidebar rail.
enum AppSection: String, CaseIterable, Identifiable {
    case smartScan, uninstaller, largeFiles, privacy

    var id: String { rawValue }
    var title: String {
        switch self {
        case .smartScan: return "Smart Scan"
        case .uninstaller: return "Uninstaller"
        case .largeFiles: return "Large & Old Files"
        case .privacy: return "Privacy"
        }
    }
    var symbol: String {
        switch self {
        case .smartScan: return "sparkles"
        case .uninstaller: return "trash"
        case .largeFiles: return "doc.viewfinder"
        case .privacy: return "hand.raised"
        }
    }
    /// The module's signature stage + accent colors.
    var theme: ModuleTheme {
        switch self {
        case .smartScan: return .magenta
        case .uninstaller: return .indigo
        case .largeFiles: return .teal
        case .privacy: return .blue
        }
    }
}

/// Top-level shell: one full-window module stage, the icon rail, and the
/// active section's content. The titlebar is hidden so the stage runs edge to
/// edge; switching modules crossfades the stage to the new signature gradient.
public struct RootView: View {
    public init() {}

    @State private var selection: AppSection = .smartScan
    // Owned here so their state (scan results, discovered apps) survives sidebar
    // switches instead of being thrown away each time the view is recreated.
    @State private var scanModel = ScanViewModel()
    @State private var uninstallModel = UninstallViewModel()
    @State private var largeFilesModel = LargeFilesViewModel()
    @State private var privacyModel = PrivacyViewModel()

    public var body: some View {
        ZStack {
            ModuleBackground(theme: selection.theme, active: stageActive)
                .id(selection)
                .transition(.opacity)

            HStack(spacing: 0) {
                Sidebar(selection: $selection)

                ZStack {
                    switch selection {
                    case .smartScan:
                        SmartScanView(model: scanModel)
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
        .frame(minWidth: 960, minHeight: 680)
        .preferredColorScheme(.dark)
    }

    /// Whether the visible module is actively scanning or cleaning — drives
    /// the stage's brighter, breathing glow.
    private var stageActive: Bool {
        switch selection {
        case .smartScan:
            return scanModel.phase == .scanning || scanModel.phase == .cleaning
        case .uninstaller:
            return uninstallModel.phase == .scanning
        case .largeFiles:
            return largeFilesModel.phase == .scanning || largeFilesModel.phase == .cleaning
        case .privacy:
            return privacyModel.phase == .scanning || privacyModel.phase == .cleaning
        }
    }
}
