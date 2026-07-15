import SwiftUI
import CleanCore

/// The 232 pt labeled glass sidebar: CleanMyMac-style nav items — a gradient
/// icon tile plus title — grouped under uppercase section headers, real disk
/// usage at the bottom. The window titlebar is hidden, so the top leaves
/// clearance for the traffic lights.
struct Sidebar: View {
    @Binding var selection: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            item(.smartScan)
                .padding(.top, 42)

            header("Cleanup")
            item(.systemJunk)
            item(.mailAttachments)
            item(.trashBins)

            header("Speed")
            item(.optimization)
            item(.maintenance)

            header("Protection")
            item(.privacy)

            header("Applications")
            item(.uninstaller)

            header("Files")
            item(.largeFiles)
            item(.spaceLens)

            Spacer(minLength: 12)

            DiskGauge()
                .padding(.horizontal, 12)

            OnyxFooter()
                .padding(.horizontal, 12)
                .padding(.top, 12)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .frame(width: 232)
        .frame(maxHeight: .infinity)
        .background(.white.opacity(0.045))
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.07)).frame(width: 1)
        }
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .tracking(1.3)
            .foregroundStyle(.white.opacity(0.32))
            .padding(.horizontal, 12)
            .padding(.top, 13)
            .padding(.bottom, 4)
    }

    private func item(_ section: AppSection) -> some View {
        NavItem(section: section, selected: selection == section) {
            withAnimation(.snappy(duration: 0.2)) { selection = section }
        }
    }
}

private struct NavItem: View {
    let section: AppSection
    let selected: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(section.dotGradient)
                    .frame(width: 27, height: 27)
                    .overlay(
                        Image(systemName: section.symbol)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color(hex: Onyx.bg0, alpha: 0.82))
                    )
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1.5)

                Text(section.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? .white : .white.opacity(0.72))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(selected ? 0.13 : (hover ? 0.06 : 0)))
            )
            .overlay(alignment: .top) {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.10), .clear],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: 14)
                        .padding(.horizontal, 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(section.title)
    }
}

// MARK: - Onyx studio signature

/// A quiet "An Onyx product" credit pinned to the foot of the sidebar: the thin
/// gem mark plus muted text, tinted in the same champagne accent and secondary
/// grey as the rest of the CleanUI palette (see `Theme.swift`).
private struct OnyxFooter: View {
    var body: some View {
        HStack(spacing: 6) {
            OnyxMark(lineWidth: 1)
                .frame(width: 9, height: 12)
                .foregroundStyle(Color(hex: Onyx.gold, alpha: 0.55))

            Text("An Onyx product")
                .font(.system(size: 9.5, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(Palette.tiny)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("An Onyx product")
    }
}

// MARK: - Real disk usage (mockup `.disk`)

private struct DiskGauge: View {
    @State private var used: Int64 = 0
    @State private var total: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Macintosh HD")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.13))
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: 0x6FD3FF), Color(hex: 0xB06CFF)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 5)
            .padding(.top, 7)
            .padding(.bottom, 5)

            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(Palette.sub)
        }
        .onAppear(perform: load)
    }

    private var fraction: CGFloat {
        total > 0 ? CGFloat(used) / CGFloat(total) : 0
    }

    private var summary: String {
        guard total > 0 else { return "—" }
        return "\(ByteFormat.human(used)) used of \(ByteFormat.human(total))"
    }

    private func load() {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let capacity = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return }
        total = Int64(capacity)
        used = Int64(capacity) - available
    }
}
