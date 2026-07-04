import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: alpha)
    }
}

// MARK: - Aurora stage

/// The one full-window backdrop: a deep violet base with three soft radial
/// color pools. Privacy uses a warmer variant. Drawn once by `RootView`;
/// screens never draw their own background.
struct AuroraBackground: View {
    enum Variant { case standard, privacy }
    var variant: Variant = .standard

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                base

                pool(top, radius: 0.85 * w)
                    .position(x: w * (variant == .privacy ? 0.70 : 0.75), y: h * -0.10)
                pool(corner, radius: 0.78 * w)
                    .position(x: w * (variant == .privacy ? 0.95 : 0.90), y: h * 1.05)
                pool(side, radius: 0.68 * w)
                    .position(x: w * -0.10, y: h * 0.90)
            }
        }
        .ignoresSafeArea()
    }

    private var base: LinearGradient {
        let stops: [Color] = variant == .privacy
            ? [Color(hex: 0x321A44), Color(hex: 0x44204E), Color(hex: 0x241436)]
            : [Color(hex: 0x221A3E), Color(hex: 0x2C1C4E), Color(hex: 0x1B1436)]
        return LinearGradient(colors: stops,
                              startPoint: UnitPoint(x: 0.15, y: 0),
                              endPoint: UnitPoint(x: 0.85, y: 1))
    }

    private var top: Color {
        variant == .privacy ? Color(hex: 0x6A2A66) : Color(hex: 0x4A2A7A)
    }
    private var corner: Color {
        variant == .privacy ? Color(hex: 0x8A2A4E) : Color(hex: 0x7A2A6A)
    }
    private var side: Color {
        variant == .privacy ? Color(hex: 0x3A2A66) : Color(hex: 0x232A66)
    }

    private func pool(_ color: Color, radius: CGFloat) -> some View {
        RadialGradient(colors: [color, color.opacity(0)],
                       center: .center, startRadius: 0, endRadius: radius)
            .frame(width: radius * 2, height: radius * 2)
    }
}

// MARK: - Palette

enum Palette {
    // Text tiers (mockup: .name .sub .tiny .slab)
    static let ink = Color.white
    static let ink2 = Color.white.opacity(0.82)
    static let sub = Color.white.opacity(0.55)
    static let tiny = Color.white.opacity(0.45)
    static let slab = Color.white.opacity(0.40)
    static let hair = Color.white.opacity(0.10)

    // Glass surfaces
    static let glassFill = Color.white.opacity(0.07)
    static let glassBorder = Color.white.opacity(0.10)
    static let glassFocusBorder = Color(hex: 0x9682FF, alpha: 0.55)
    static let glassFocusGlow = Color(hex: 0x785AFF, alpha: 0.25)

    // Primary action gradient (buttons)
    static let action = LinearGradient(colors: [Color(hex: 0x5A8DFF), Color(hex: 0x9A5BFF)],
                                       startPoint: .leading, endPoint: .trailing)
    static let actionDiagonal = LinearGradient(colors: [Color(hex: 0x5A8DFF), Color(hex: 0x8F5BFF)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
    static let actionGlow = Color(hex: 0x785AFF)

    // Checkbox-on gradient
    static let check = LinearGradient(colors: [Color(hex: 0x8F5BFF), Color(hex: 0xC04AE0)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
    static let checkGlow = Color(hex: 0x8F5BFF, alpha: 0.5)

    // Bottom bar fill
    static let barFill = Color(hex: 0x140E28, alpha: 0.5)
}

// MARK: - Status pill tones

enum PillTone {
    case good, warn, blue, red

    var text: Color {
        switch self {
        case .good: return Color(hex: 0x7BE8A8)
        case .warn: return Color(hex: 0xFFC37B)
        case .blue: return Color(hex: 0xAEB8FF)
        case .red:  return Color(hex: 0xFF9DAE)
        }
    }

    var fill: Color {
        switch self {
        case .good: return Color(hex: 0x5FE096, alpha: 0.15)
        case .warn: return Color(hex: 0xFFAA5A, alpha: 0.15)
        case .blue: return Color(hex: 0x7A8CFF, alpha: 0.18)
        case .red:  return Color(hex: 0xFF6E82, alpha: 0.16)
        }
    }
}

// MARK: - Frosted glass surface

/// Translucent white glass per the mockup (`.glass`): white 0.07 fill, white
/// 0.10 hairline. Deliberately NOT a system material — materials sample the
/// backdrop, which renders black in offscreen snapshots and hides the aurora.
struct GlassCard: ViewModifier {
    var radius: CGFloat = 14
    var focused: Bool = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Palette.glassFill))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(focused ? Palette.glassFocusBorder : Palette.glassBorder, lineWidth: 1)
            )
            .shadow(color: focused ? Palette.glassFocusGlow : .clear, radius: 12)
    }
}

extension View {
    func glassCard(radius: CGFloat = 14, focused: Bool = false) -> some View {
        modifier(GlassCard(radius: radius, focused: focused))
    }
}
