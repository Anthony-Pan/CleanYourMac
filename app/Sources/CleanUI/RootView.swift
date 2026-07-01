import SwiftUI

/// App sections shown in the custom sidebar.
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
    var isLive: Bool { self == .smartScan || self == .uninstaller }
}

/// Top-level shell: a fully custom dark sidebar + the active section. No
/// NavigationSplitView — everything is hand-styled to the dark glass theme,
/// and the window titlebar is hidden so content runs edge to edge.
public struct RootView: View {
    public init() {}

    @State private var selection: AppSection = .smartScan

    public var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $selection)

            ZStack {
                switch selection {
                case .smartScan:
                    SmartScanView()
                case .uninstaller:
                    UninstallerView()
                default:
                    ComingSoonView(title: selection.title, symbol: selection.symbol)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 920, minHeight: 660)
        .background(Palette.bg)
        .preferredColorScheme(.dark)
    }
}
