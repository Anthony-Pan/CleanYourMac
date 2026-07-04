import SwiftUI
import CleanCore

/// Real app screens rendered with preloaded mock state (no disk access), for
/// off-screen design snapshots via ImageRenderer. Each case composes exactly
/// what `RootView` would show — the module stage, the sidebar rail, and the
/// actual module view — so the render is the design, not a copy of it.
public enum SnapshotScreen: String, CaseIterable {
    case smartScanIdle, smartScanResults, uninstaller, largeFiles, privacyIdle

    /// The full window (stage + rail + module view) at a fixed design size.
    @MainActor
    public var view: some View {
        ZStack {
            ModuleBackground(theme: section.theme, active: false)
            HStack(spacing: 0) {
                Sidebar(selection: .constant(section))
                // Mirror RootView: the module view fills the space right of the rail.
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 1180, height: 780)
        .environment(\.colorScheme, .dark)
    }

    private var section: AppSection {
        switch self {
        case .smartScanIdle, .smartScanResults: return .smartScan
        case .uninstaller:                      return .uninstaller
        case .largeFiles:                       return .largeFiles
        case .privacyIdle:                      return .privacy
        }
    }

    @MainActor
    @ViewBuilder private var content: some View {
        switch self {
        case .smartScanIdle:
            SmartScanView(model: ScanViewModel())
        case .smartScanResults:
            SmartScanView(model: ScanViewModel(mockGroups: Self.mockGroups(), expandFirst: false))
        case .uninstaller:
            UninstallerView(model: UninstallViewModel(
                mockApps: Self.mockApps(),
                runningBundleIDs: ["com.tinyspeck.slackmacgap"]))
        case .largeFiles:
            LargeFilesView(model: LargeFilesViewModel(mockFiles: Self.mockFiles()))
        case .privacyIdle:
            PrivacyView(model: PrivacyViewModel())
        }
    }

    // MARK: - Mock data (plausible, deterministic, never touches the disk)

    private static func mockGroups() -> [ScanResultGroup] {
        func group(_ id: String, _ name: String, _ files: [(String, Int64)]) -> ScanResultGroup {
            let items = files.map { (name, size) in
                ScanItem(url: URL(fileURLWithPath: "/Users/you/Library/Caches/\(name)"),
                         categoryID: id, sizeBytes: size, modificationDate: nil)
            }
            let cat = CleanupCategory(id: id, nameEN: name, nameCN: name, targets: [])
            return ScanResultGroup(category: cat, items: items)
        }
        return [
            group("user-caches", "User Caches", Array(repeating: ("cache", 811_000_000), count: 129)),
            group("dev-tool-caches", "Developer Tool Caches", Array(repeating: ("cache", 2_150_000_000), count: 11)),
            group("xcode-derived-data", "Xcode Derived Data", Array(repeating: ("build", 660_000_000), count: 5)),
            group("app-logs", "Application Logs", Array(repeating: ("log", 2_000_000), count: 48)),
        ]
    }

    private static func mockApps() -> [InstalledApp] {
        func app(_ name: String, _ bundleID: String?, _ version: String?,
                 _ sizeBytes: Int64, system: Bool = false) -> InstalledApp {
            InstalledApp(url: URL(fileURLWithPath: "/Applications/\(name).app"),
                         name: name, bundleID: bundleID, version: version,
                         sizeBytes: sizeBytes, isSystem: system)
        }
        return [
            app("Docker", "com.docker.docker", "4.30.0", 2_840_000_000),
            app("Google Chrome", "com.google.Chrome", "126.0.6478", 1_230_000_000),
            app("Slack", "com.tinyspeck.slackmacgap", "4.39.90", 452_000_000),
            app("Spotify", "com.spotify.client", "1.2.40", 386_000_000),
            app("Safari", "com.apple.Safari", "17.5", 15_000_000, system: true),
            app("zoom.us", "us.zoom.xos", "6.1.1", 158_000_000),
        ]
    }

    private static func mockFiles() -> [LargeFile] {
        func file(_ folder: String, _ name: String, _ sizeBytes: Int64,
                  _ ageDays: Int, _ kind: FileKind) -> LargeFile {
            let date = Date().addingTimeInterval(-Double(ageDays) * 86_400)
            return LargeFile(url: URL(fileURLWithPath: "/Users/you/\(folder)/\(name)"),
                             sizeBytes: sizeBytes, modificationDate: date,
                             accessDate: date, kind: kind)
        }
        return [
            file("Downloads", "ubuntu-24.04.1-desktop-arm64.iso", 5_890_000_000, 410, .diskImage),
            file("Downloads", "Xcode_15.4.dmg", 3_310_000_000, 290, .diskImage),
            file("Movies", "keynote-rehearsal-4k.mov", 3_240_000_000, 95, .video),
            file("Documents", "design-assets-2024.zip", 1_870_000_000, 240, .archive),
            file("Music", "band-practice-master.aiff", 1_120_000_000, 530, .audio),
            file("Movies", "drone-footage-croatia.mp4", 890_000_000, 60, .video),
        ]
    }
}
