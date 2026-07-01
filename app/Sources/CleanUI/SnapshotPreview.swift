import SwiftUI
import CleanCore

/// A static, mock-data rendering of the full app (custom sidebar + Smart Scan
/// card grid). Rendered off-screen via ImageRenderer for design review.
public struct SnapshotPreview: View {
    public init() {}

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

    @State private var model = ScanViewModel(mockGroups: SnapshotPreview.mockGroups(), expandFirst: false)

    public var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: .constant(.smartScan))
            content
        }
        .frame(width: 980, height: 760)
        .background(Palette.bg)
        .environment(\.colorScheme, .dark)
    }

    private var content: some View {
        ZStack {
            StageBackground(glow: false)
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("SMART SCAN")
                        .font(.system(size: 11, weight: .semibold)).tracking(1.6)
                        .foregroundStyle(Palette.muted)
                    Text("\(ByteFormat.human(model.selectedBytes)) to reclaim")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                    Text("\(model.selectedItemCount) items across \(model.groups.count) categories")
                        .font(.callout).foregroundStyle(Palette.muted)
                }
                .padding(.top, 46)
                .padding(.bottom, 22)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(model.groups) { g in
                        CategoryGridCard(group: g, model: model) {}
                    }
                }
                .padding(.horizontal, 28)

                Spacer()

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(model.selectedItemCount) items selected")
                            .font(.subheadline).foregroundStyle(Palette.ink)
                        Text("Everything goes to the Trash — recoverable")
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    CleanButton(size: model.selectedBytes, disabled: false) {}
                }
                .padding(16)
                .background(Palette.bg.opacity(0.55))
            }
        }
    }
}
