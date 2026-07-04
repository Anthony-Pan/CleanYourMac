import SwiftUI

/// CleanMyMac-5-style icon rail: a narrow strip of glassy square tiles over
/// the module stage, darkened so the active module's gradient shows through.
/// Labels live in tooltips; the window titlebar is hidden, so the rail leaves
/// room for the traffic lights at the top.
struct Sidebar: View {
    @Binding var selection: AppSection

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                ForEach(AppSection.allCases) { section in
                    RailTile(section: section, selected: selection == section) {
                        withAnimation(.snappy(duration: 0.25)) { selection = section }
                    }
                }
            }
            .padding(.top, 54)

            Spacer()

            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .help("Files go to the Trash — recoverable")
                .padding(.bottom, 16)
        }
        .frame(width: 68)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.30))
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.07)).frame(width: 1)
        }
    }
}

private struct RailTile: View {
    let section: AppSection
    let selected: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(selected ? 0.20 : (hover ? 0.10 : 0.05)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(selected ? 0.30 : 0.10), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: section.symbol)
                        .font(.system(size: 16, weight: selected ? .semibold : .regular))
                        .foregroundStyle(.white.opacity(selected ? 1 : 0.60))
                )
                .frame(width: 42, height: 42)
                .shadow(color: .black.opacity(selected ? 0.25 : 0), radius: 8, y: 4)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(section.title)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .accessibilityLabel(section.title)
    }
}
