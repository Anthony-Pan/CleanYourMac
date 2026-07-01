import SwiftUI

/// Hand-built dark sidebar (no system List / NavigationSplitView chrome).
struct Sidebar: View {
    @Binding var selection: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.top, 42)
                .padding(.horizontal, 18)
                .padding(.bottom, 22)

            Text("TOOLS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Palette.muted.opacity(0.7))
                .padding(.horizontal, 22)
                .padding(.bottom, 8)

            VStack(spacing: 4) {
                ForEach(AppSection.allCases) { section in
                    SidebarRow(section: section, selected: selection == section) {
                        withAnimation(.snappy(duration: 0.2)) { selection = section }
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            footer
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
        }
        .frame(width: 236)
        .frame(maxHeight: .infinity)
        .background(sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
        }
    }

    private var brand: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.accentLinear)
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.85)))
                .shadow(color: Palette.accent.opacity(0.45), radius: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text("CleanYourMac")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text("Safe cleanup")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 11))
                .foregroundStyle(Palette.accent.opacity(0.9))
            Text("Files go to Trash")
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
            Spacer()
            Text("v0.1")
                .font(.system(size: 10))
                .foregroundStyle(Palette.muted.opacity(0.6))
        }
    }

    private var sidebarBackground: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x241148), Color(hex: 0x0E0620)],
                           startPoint: .top, endPoint: .bottom)
            // faint aqua glow behind the brand
            RadialGradient(colors: [Palette.accent.opacity(0.12), .clear],
                           center: .init(x: 0.3, y: 0.02), startRadius: 4, endRadius: 190)
        }
        .ignoresSafeArea()
    }
}

private struct SidebarRow: View {
    let section: AppSection
    let selected: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: section.symbol)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.accent : Palette.muted)
                    .frame(width: 22)

                Text(section.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.ink : Palette.ink2.opacity(0.75))

                Spacer(minLength: 4)

                if !section.isLive {
                    Text("soon")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.06)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(rowBackground)
            .overlay(alignment: .leading) {
                if selected {
                    Capsule().fill(Palette.accent)
                        .frame(width: 3, height: 17)
                        .shadow(color: Palette.accent.opacity(0.7), radius: 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!section.isLive)
        .onHover { hover = $0 }
    }

    @ViewBuilder private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(selected ? Palette.accent.opacity(0.13) : (hover ? Color.white.opacity(0.045) : .clear))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Palette.accent.opacity(0.22) : .clear, lineWidth: 1)
            )
    }
}
