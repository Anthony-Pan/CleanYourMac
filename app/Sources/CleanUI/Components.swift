import SwiftUI
import AppKit
import CleanCore

// MARK: - Per-category icon style (colored tile on a glass card)

struct CategoryStyle {
    let symbol: String
    let a: Color
    let b: Color

    var gradient: LinearGradient { LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing) }
    var glow: Color { a }

    static func forID(_ id: String) -> CategoryStyle {
        switch id {
        case "user-caches":        return .init(symbol: "internaldrive.fill", a: Color(hex: 0x22E0C8), b: Color(hex: 0x2A6BF5))
        case "dev-tool-caches":    return .init(symbol: "shippingbox.fill", a: Color(hex: 0x6A7BFF), b: Color(hex: 0x8B3DF5))
        case "xcode-derived-data": return .init(symbol: "hammer.fill", a: Color(hex: 0xFFB65C), b: Color(hex: 0xFF5E9C))
        case "app-logs":           return .init(symbol: "doc.text.fill", a: Color(hex: 0x43E27D), b: Color(hex: 0x17B0A0))
        default:                   return .init(symbol: "folder.fill", a: Color(hex: 0x8A8FA8), b: Color(hex: 0x565A70))
        }
    }
}

// MARK: - Hero blob (the module's centerpiece artwork)

/// A soft eight-lobed "flower blob" — two stacked continuous-corner squares,
/// one rotated 45° — standing in for CleanMyMac's 3D mascots. Carries the
/// module's glow colors and a big white symbol.
struct HeroBlob: View {
    let theme: ModuleTheme
    let symbol: String
    var animating: Bool = false
    var size: CGFloat = 196

    @State private var breathe = false

    private var fill: LinearGradient {
        LinearGradient(colors: [theme.glow.opacity(0.95), theme.accent.opacity(0.55)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            lobe.rotationEffect(.degrees(45))
            lobe
        }
        .compositingGroup()
        .shadow(color: theme.deep.opacity(0.55), radius: 28, y: 18)
        .overlay(
            Image(systemName: symbol)
                .font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        )
        .frame(width: size, height: size)
        .scaleEffect(animating && breathe ? 1.05 : 1)
        .animation(animating ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true) : .snappy,
                   value: breathe)
        .onAppear { breathe = true }
    }

    private var lobe: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.30), .clear],
                                         startPoint: .top, endPoint: .center))
            )
            .frame(width: size * 0.74, height: size * 0.74)
    }
}

// MARK: - Circular primary action button

/// The large round Scan / Stop / Clean button pinned at the bottom center of
/// every module, ringed like CleanMyMac's. `.halo` is a static ring;
/// `.progress` spins an arc around the circle while work is running.
struct CircleActionButton: View {
    enum Ring { case none, halo, progress }

    let title: String
    let theme: ModuleTheme
    var ring: Ring = .halo
    var disabled: Bool = false
    let action: () -> Void

    @State private var spin = false
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            ZStack {
                ringView

                Circle()
                    .fill(theme.accentGradient)
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .frame(width: 72, height: 72)
                    .shadow(color: theme.accent.opacity(disabled ? 0 : 0.55),
                            radius: hover ? 26 : 18, y: 6)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .frame(width: 62)
            }
            .frame(width: 94, height: 94)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .scaleEffect(hover && !disabled ? 1.04 : 1)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .onAppear { startSpin() }
        .onChange(of: ring == .progress) { _, _ in startSpin() }
    }

    @ViewBuilder private var ringView: some View {
        switch ring {
        case .none:
            EmptyView()
        case .halo:
            Circle()
                .strokeBorder(.white.opacity(0.28), lineWidth: 1.5)
                .frame(width: 88, height: 88)
        case .progress:
            Circle()
                .strokeBorder(.white.opacity(0.16), lineWidth: 2)
                .frame(width: 88, height: 88)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 86, height: 86)
                .rotationEffect(.degrees(spin ? 360 : 0))
        }
    }

    private func startSpin() {
        spin = false
        guard ring == .progress else { return }
        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
    }
}

// MARK: - Glass capsule button (secondary actions)

struct GlassPill: View {
    let title: String
    var systemImage: String?
    var prominent: Bool = false
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                }
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(Capsule().fill(.white.opacity(baseOpacity + (hover ? 0.05 : 0))))
            .overlay(Capsule().strokeBorder(.white.opacity(prominent ? 0.34 : 0.22), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var baseOpacity: Double { prominent ? 0.20 : 0.10 }
}

// MARK: - Tiny status chip

struct TagBadge: View {
    let text: String
    var color: Color = Palette.warn

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

// MARK: - Category result card (frosted glass, tap anywhere → detail)

struct CategoryGridCard: View {
    let group: ScanResultGroup
    let model: ScanViewModel
    let onOpen: () -> Void

    @State private var hover = false
    private var style: CategoryStyle { .forID(group.category.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(style.gradient)
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: style.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white))
                    .shadow(color: style.glow.opacity(0.45), radius: 9, y: 4)

                Spacer()

                Button { model.toggleCategory(group) } label: {
                    Image(systemName: masterIcon)
                        .font(.system(size: 21))
                        .foregroundStyle(masterOn ? Color.white : .white.opacity(0.30))
                }
                .buttonStyle(.plain)
                .help(masterOn ? "Deselect all in this category" : "Select all in this category")
            }

            Spacer(minLength: 10)

            Text(ByteFormat.human(group.totalBytes))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(group.category.nameEN)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.top, 1)

            HStack {
                Text("\(group.items.count) items")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                Spacer()
                GlassPill(title: "Review", action: onOpen)
            }
            .padding(.top, 9)
        }
        .padding(16)
        .frame(height: 172)
        .glassCard(radius: 16, focused: hover)
        .scaleEffect(hover ? 1.012 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { onOpen() }
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }

    private var masterOn: Bool { model.categoryState(group) != .none }

    private var masterIcon: String {
        switch model.categoryState(group) {
        case .all:  return "checkmark.circle.fill"
        case .some: return "minus.circle.fill"
        case .none: return "circle"
        }
    }
}

// MARK: - One file row (used in detail lists)

struct ItemRow: View {
    let item: ScanItem
    let selected: Bool
    let color: Color
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? color : .white.opacity(0.28))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
                Text(item.path)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(ByteFormat.human(item.sizeBytes))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.muted)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 14)
    }
}
