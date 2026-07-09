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

// MARK: - Tiny status chip

struct TagBadge: View {
    let text: String
    var color: Color = PillTone.warn.text

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

// MARK: - Aurora components (per DESIGN.md / the Claude Design mockup)

/// The glossy 3D sphere with halo glow and two satellite orbs — the app's
/// centerpiece on idle and busy screens (mockup `.orb`).
struct Orb: View {
    var size: CGFloat = 230
    var animating: Bool = false

    @State private var breathe = false

    var body: some View {
        ZStack {
            // Halo glow
            RadialGradient(colors: [Color(hex: 0x7896FF, alpha: 0.45),
                                    Color(hex: 0xA05AFF, alpha: 0.25),
                                    .clear],
                           center: .center, startRadius: 0, endRadius: size * 0.72)
                .frame(width: size * 1.44, height: size * 1.44)
                .blur(radius: 24)

            // Body
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xBCD6FF),
                                              Color(hex: 0x7FA0FF),
                                              Color(hex: 0x8F5BFF),
                                              Color(hex: 0x5A3AB8)],
                                     center: UnitPoint(x: 0.32, y: 0.28),
                                     startRadius: 0, endRadius: size * 0.72))
                .frame(width: size * 0.72, height: size * 0.72)
                .overlay( // top gloss
                    Circle().fill(
                        LinearGradient(colors: [.white.opacity(0.45), .clear],
                                       startPoint: .top, endPoint: .center))
                        .frame(width: size * 0.52, height: size * 0.30)
                        .blur(radius: 6)
                        .offset(y: -size * 0.20)
                )
                .shadow(color: Color(hex: 0x3C1E8C, alpha: 0.6), radius: 30, y: 20)
                .scaleEffect(animating && breathe ? 1.04 : 1)

            satellite(Color(hex: 0xFFD6F2), Color(hex: 0xE05BBF), d: size * 0.15)
                .offset(x: -size * 0.34, y: -size * 0.14)
            satellite(Color(hex: 0xD6FFF2), Color(hex: 0x2FD4A0), d: size * 0.09)
                .offset(x: size * 0.33, y: size * 0.16)
        }
        .frame(width: size, height: size)
        .animation(animating ? .easeInOut(duration: 1.8).repeatForever(autoreverses: true) : .snappy,
                   value: breathe)
        .onAppear { breathe = true }
        .accessibilityHidden(true)
    }

    private func satellite(_ hi: Color, _ lo: Color, d: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [hi, lo],
                                 center: UnitPoint(x: 0.35, y: 0.30),
                                 startRadius: 0, endRadius: d * 0.8))
            .frame(width: d, height: d)
            .shadow(color: lo.opacity(0.5), radius: 10, y: 6)
    }
}

/// The 104 pt circular primary button on idle screens (mockup `.cta`).
struct CTACircle: View {
    let title: String
    var disabled: Bool = false
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Palette.actionDiagonal)
                    .overlay( // top-left gloss
                        Circle().fill(
                            RadialGradient(colors: [.white.opacity(0.35), .clear],
                                           center: UnitPoint(x: 0.32, y: 0.26),
                                           startRadius: 0, endRadius: 52))
                    )
                    .overlay(Circle().strokeBorder(.white.opacity(0.30), lineWidth: 1))

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .frame(width: 88)
            }
            .frame(width: 104, height: 104)
            .background( // halo ring
                Circle().fill(Palette.actionGlow.opacity(disabled ? 0 : 0.14))
                    .frame(width: 120, height: 120)
            )
            .shadow(color: Palette.actionGlow.opacity(disabled ? 0 : (hover ? 0.7 : 0.55)),
                    radius: hover ? 34 : 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .scaleEffect(hover && !disabled ? 1.03 : 1)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

/// Bottom-bar primary button (mockup `.btn`): radius-10 gradient rectangle.
struct GradientButton: View {
    let title: String
    var disabled: Bool = false
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.action)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.30), lineWidth: 1))
                )
                .shadow(color: Palette.actionGlow.opacity(disabled ? 0 : 0.4),
                        radius: hover ? 16 : 11, y: 5)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}

/// Bottom-bar secondary button (mockup `.btn.ghost`).
struct GhostButton: View {
    let title: String
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(hover ? 0.14 : 0.10))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.16), lineWidth: 1))
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Status chip in the top bar and on rows (mockup `.pill`).
struct StatusPill: View {
    let text: String
    var tone: PillTone = .blue

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tone.text)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(Capsule().fill(tone.fill))
    }
}

/// Rounded-square selection checkbox (mockup `.cb`): purple gradient + white
/// check when on, gradient + white minus when mixed (partial selection),
/// hairline square when off.
struct GlassCheckbox: View {
    let state: CheckState
    let action: () -> Void

    init(state: CheckState, action: @escaping () -> Void) {
        self.state = state
        self.action = action
    }

    /// Two-state convenience for plain on/off rows (leftovers, privacy traces).
    init(on: Bool, action: @escaping () -> Void) {
        self.init(state: on ? .on : .off, action: action)
    }

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(state == .off ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Palette.check))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(.white.opacity(state == .off ? 0.30 : 0), lineWidth: 1.5)
                )
                .overlay {
                    if state != .off {
                        Image(systemName: state == .on ? "checkmark" : "minus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 16, height: 16)
                .shadow(color: state == .off ? .clear : Palette.checkGlow, radius: 4, y: 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared size presentation (list rows everywhere)

/// The one "data number" style for trailing sizes: 13.5 pt semibold white-0.82
/// with monospaced digits so streaming updates don't wobble. `emphasized`
/// lifts the largest row to pure white.
struct SizeText: View {
    private let text: String
    private let emphasized: Bool

    init(_ bytes: Int64, emphasized: Bool = false) {
        self.init(ByteFormat.human(bytes), emphasized: emphasized)
    }

    init(_ text: String, emphasized: Bool = false) {
        self.text = text
        self.emphasized = emphasized
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(emphasized ? Color.white : Palette.ink2)
    }
}

/// A thin capsule showing a row's size relative to the biggest visible row.
/// Real bytes only — renders nothing when `max` is unknown or zero.
struct RelativeSizeBar: View {
    let value: Int64
    let max: Int64
    var gradient: LinearGradient = Palette.action
    var height: CGFloat = 3

    var body: some View {
        if max > 0 {
            GeometryReader { geo in
                Capsule()
                    .fill(gradient)
                    .frame(width: barWidth(in: geo.size.width))
            }
            .frame(height: height)
        }
    }

    /// Proportional width, floored at 2 pt so tiny-but-real values stay visible.
    private func barWidth(in available: CGFloat) -> CGFloat {
        guard value > 0 else { return 0 }
        return Swift.max(2, available * CGFloat(value) / CGFloat(max))
    }
}

/// Shimmer placeholder for a size that hasn't been computed yet. Fixed
/// footprint so nothing reflows when the real number lands. Never shows a
/// fake "0 B".
struct SizePending: View {
    var width: CGFloat = 52

    @State private var dimmed = false

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.08))
            .frame(width: width, height: 12)
            .opacity(dimmed ? 0.5 : 1)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: dimmed)
            .onAppear { dimmed = true }
    }
}

/// 56 pt screen header (mockup `.tbar`): 19 pt bold title left, trailing
/// content (usually a StatusPill) right.
struct TopBar<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            trailing
        }
        .padding(.horizontal, 26)
        .frame(height: 56)
    }
}

/// 70 pt bottom action bar (mockup `.bbar`).
struct BottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 14) { content }
            .padding(.horizontal, 26)
            .frame(height: 70)
            .frame(maxWidth: .infinity)
            .background(Palette.barFill)
            .overlay(alignment: .top) { Rectangle().fill(Palette.hair).frame(height: 1) }
    }
}

/// Glass stat tile on the idle dashboard (mockup `.stat`). Real data only.
struct StatCard: View {
    let label: String
    let value: String
    var detail: String = ""
    var valueColor: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Palette.slab)
            Text(value)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(valueColor)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 14)
    }
}
