import SwiftUI
import CleanCore

/// Real app screens rendered with preloaded mock state (no disk access), for
/// off-screen design snapshots via ImageRenderer. Each case composes exactly
/// what `RootView` would show — the module stage, the sidebar rail, and the
/// actual module view — so the render is the design, not a copy of it.
public enum SnapshotScreen: String, CaseIterable {
    case smartScanIdle, smartScanResults, uninstaller, largeFiles, privacyIdle, privacyResults

    /// The full window (stage + rail + module view) at a fixed design size.
    @MainActor
    public var view: some View {
        ZStack {
            AuroraBackground(variant: section == .privacy ? .privacy : .standard)
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
        case .privacyIdle, .privacyResults:     return .privacy
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
        case .privacyResults:
            PrivacyView(model: PrivacyViewModel(
                mockGroups: Self.mockPrivacyGroups(),
                mockFindings: Self.mockFindings()))
        }
    }

    // MARK: - Mock data (plausible, deterministic, never touches the disk)

    private static func mockGroups() -> [ScanResultGroup] {
        // Item IDs are paths, so every mock file needs a unique name — repeated
        // names collapse to one row in ForEach. Category details are the real
        // `detailEN` copy from `CleanupCategory.mvpUserSafe`, never invented.
        func group(_ id: String, _ name: String, _ detail: String,
                   _ stem: String, _ size: Int64, _ count: Int) -> ScanResultGroup {
            let items = (0..<count).map { i in
                ScanItem(url: URL(fileURLWithPath: "/Users/you/Library/Caches/\(stem)-\(i)"),
                         categoryID: id, sizeBytes: size, modificationDate: nil)
            }
            let cat = CleanupCategory(id: id, nameEN: name, nameCN: name,
                                      detailEN: detail, targets: [])
            return ScanResultGroup(category: cat, items: items)
        }
        return [
            group("user-caches", "User Caches",
                  "App caches that are rebuilt automatically.",
                  "com.example.cache", 811_000_000, 129),
            group("dev-tool-caches", "Developer Tool Caches",
                  "npm / Gradle / CocoaPods download caches.",
                  "registry-shard", 2_150_000_000, 11),
            group("xcode-derived-data", "Xcode Derived Data",
                  "Build intermediates Xcode regenerates on next build.",
                  "MyApp-build", 660_000_000, 5),
            group("app-logs", "Application Logs",
                  "Diagnostic logs written by apps.",
                  "diagnostics", 2_000_000, 48),
        ]
    }

    private static func mockPrivacyGroups() -> [PrivacyGroup] {
        func item(_ app: PrivacyApp, _ kind: PrivacyItemKind, _ path: String,
                  _ size: Int64, context: String? = nil) -> PrivacyItem {
            PrivacyItem(app: app, kind: kind,
                        url: URL(fileURLWithPath: "/Users/you/Library/\(path)"),
                        sizeBytes: size, context: context)
        }
        let slack = PrivacyApp.electron(name: "Slack", bundleID: "com.tinyspeck.slackmacgap")
        return [
            PrivacyGroup(app: .chrome, items: [
                item(.chrome, .caches, "Caches/Google/Chrome", 512_000_000),
                item(.chrome, .history, "Application Support/Google/Chrome/Default/History", 84_000_000),
                item(.chrome, .cookies, "Application Support/Google/Chrome/Default/Network/Cookies", 12_000_000),
                item(.chrome, .history, "Application Support/Google/Chrome/Profile 1/History",
                     9_000_000, context: "Profile 1"),
            ]),
            PrivacyGroup(app: slack, items: [
                item(slack, .caches, "Application Support/Slack/Cache", 310_000_000),
                item(slack, .cookies, "Application Support/Slack/Cookies", 2_000_000),
                item(slack, .siteData, "Application Support/Slack/Local Storage", 26_000_000),
            ]),
            PrivacyGroup(app: .quarantine, items: [
                item(.quarantine, .downloadRecords,
                     "Preferences/com.apple.LaunchServices.QuarantineEventsV2", 20_480),
            ]),
            PrivacyGroup(app: .shellHistory, items: [
                item(.shellHistory, .shellHistory, "../.zsh_history", 112_000),
            ]),
        ]
    }

    private static func mockFindings() -> [PrivacyFinding] {
        // Titles/details mirror the real auditor's phrasing so the snapshot
        // shows the design under true copy lengths — never invented data shapes.
        [
            PrivacyFinding(
                id: "firewall-off", severity: .warning, category: .systemSettings,
                title: "Firewall is turned off",
                detail: "The macOS application firewall is not blocking incoming connections.",
                recommendation: "Turn on the firewall in System Settings.",
                settingsURLString: "x-apple.systempreferences:com.apple.Firewall-Settings.extension"),
            PrivacyFinding(
                id: "tcc-screencapture", severity: .warning, category: .permissions,
                title: "2 apps can record your screen",
                detail: "com.example.meet, com.example.snap",
                recommendation: "Review screen recording access in System Settings.",
                settingsURLString: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
                apps: ["com.example.meet", "com.example.snap"]),
            PrivacyFinding(
                id: "airdrop-everyone", severity: .advisory, category: .networkExposure,
                title: "AirDrop is discoverable by everyone",
                detail: "Nearby strangers can see this Mac and send it files.",
                recommendation: "Set AirDrop to Contacts Only when not in use.",
                settingsURLString: nil),
            PrivacyFinding(
                id: "analytics-on", severity: .info, category: .systemSettings,
                title: "Mac analytics sharing is on",
                detail: "Diagnostics and usage data are shared with Apple.",
                recommendation: "Review analytics sharing in System Settings.",
                settingsURLString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Analytics"),
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
