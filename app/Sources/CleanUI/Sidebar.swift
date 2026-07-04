import SwiftUI
import CleanCore

/// The 210 pt labeled glass sidebar from the mockup: gradient-dot nav items
/// under uppercase section headers, real disk usage at the bottom. The window
/// titlebar is hidden, so the top leaves clearance for the traffic lights.
struct Sidebar: View {
    @Binding var selection: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            item(.smartScan)
                .padding(.top, 44)

            header("Cleanup")
            item(.largeFiles)

            header("Protection")
            item(.privacy)

            header("Applications")
            item(.uninstaller)

            Spacer()

            DiskGauge()
                .padding(.horizontal, 12)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 16)
        .frame(width: 210)
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
            .padding(.top, 15)
            .padding(.bottom, 5)
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
            HStack(spacing: 10) {
                Circle()
                    .fill(section.dotGradient)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)

                Text(section.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(selected ? .white : .white.opacity(0.72))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(selected ? 0.13 : (hover ? 0.06 : 0)))
            )
            .overlay(alignment: .top) {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.10), .clear],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: 12)
                        .padding(.horizontal, 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(section.title)
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
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.4))
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
