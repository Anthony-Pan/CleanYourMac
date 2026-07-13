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

// MARK: - ONYX brand tokens
//
// Sampled from the Onyx studio site (onyx-lab.com): a near-black cool base,
// warm champagne accent, cream text, cool-grey secondaries. Deliberately
// restrained and editorial — the opposite of a saturated gradient look.

enum Onyx {
    static let bg0:    UInt = 0x0A0A0B   // page base (near-black)
    static let bg1:    UInt = 0x0E0E10   // raised surface
    static let cream:  UInt = 0xF5F4F2   // primary text (warm off-white)
    static let grey:   UInt = 0x8A8A8F   // secondary text (cool grey)
    static let grey2:  UInt = 0x7C7C82   // tertiary text
    static let gold:   UInt = 0xC9B896   // signature champagne accent
    static let goldHi: UInt = 0xDBCBA6   // champagne highlight (gradient top)
    static let goldLo: UInt = 0xB79E72   // deeper sand (gradient bottom)
}

// MARK: - Onyx stage

/// The one full-window backdrop: a near-black base with a faint warm champagne
/// bloom — an "obsidian" surface, not a colored gradient. Privacy uses a
/// slightly warmer variant. Drawn once by `RootView`; screens never draw their
/// own background. (Struct name kept for call-site stability.)
struct AuroraBackground: View {
    enum Variant { case standard, privacy }
    var variant: Variant = .standard

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                base

                // Faint warm bloom near the top (hero), like the Onyx site.
                pool(topGlow, radius: 0.80 * w)
                    .position(x: w * (variant == .privacy ? 0.62 : 0.68), y: h * -0.02)
                // A second, fainter bloom low on the page.
                pool(cornerGlow, radius: 0.72 * w)
                    .position(x: w * (variant == .privacy ? 0.85 : 0.80), y: h * 1.06)
            }
        }
        .ignoresSafeArea()
    }

    private var base: LinearGradient {
        let stops: [Color] = variant == .privacy
            ? [Color(hex: 0x121013), Color(hex: 0x0D0B0C), Color(hex: 0x080708)]
            : [Color(hex: 0x101012), Color(hex: Onyx.bg0), Color(hex: 0x070708)]
        return LinearGradient(colors: stops,
                              startPoint: UnitPoint(x: 0.2, y: 0),
                              endPoint: UnitPoint(x: 0.8, y: 1))
    }

    // Warm, low-opacity glows. Privacy leans a touch more amber.
    private var topGlow: Color {
        variant == .privacy ? Color(hex: 0xC79A66, alpha: 0.10) : Color(hex: Onyx.gold, alpha: 0.085)
    }
    private var cornerGlow: Color {
        variant == .privacy ? Color(hex: 0xB6784C, alpha: 0.07) : Color(hex: Onyx.goldLo, alpha: 0.05)
    }

    private func pool(_ color: Color, radius: CGFloat) -> some View {
        RadialGradient(colors: [color, color.opacity(0)],
                       center: .center, startRadius: 0, endRadius: radius)
            .frame(width: radius * 2, height: radius * 2)
    }
}

// MARK: - Palette

enum Palette {
    // Text tiers (mockup roles: .name .sub .tiny .slab). Cream primary, cool
    // grey secondaries — matching the Onyx pairing of warm text on cool greys.
    static let ink = Color(hex: Onyx.cream)
    static let ink2 = Color(hex: Onyx.cream, alpha: 0.80)
    static let sub = Color(hex: Onyx.grey)
    static let tiny = Color(hex: Onyx.grey2)
    static let slab = Color(hex: Onyx.grey2, alpha: 0.85)
    static let hair = Color(hex: Onyx.cream, alpha: 0.09)

    // Glass surfaces (cream-tinted so hairlines read warm on the dark base).
    static let glassFill = Color(hex: Onyx.cream, alpha: 0.045)
    static let glassBorder = Color(hex: Onyx.cream, alpha: 0.09)
    static let glassFocusBorder = Color(hex: Onyx.gold, alpha: 0.55)
    static let glassFocusGlow = Color(hex: Onyx.gold, alpha: 0.22)

    // Primary action — champagne, not blue/violet. Dark text sits on top.
    static let action = LinearGradient(colors: [Color(hex: Onyx.goldHi), Color(hex: Onyx.goldLo)],
                                       startPoint: .leading, endPoint: .trailing)
    static let actionDiagonal = LinearGradient(colors: [Color(hex: Onyx.goldHi), Color(hex: Onyx.goldLo)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
    static let actionGlow = Color(hex: Onyx.gold)
    /// Text/glyph color that sits on top of the champagne action fill.
    static let onAction = Color(hex: Onyx.bg0)

    // Checkbox-on — champagne fill, dark glyph.
    static let check = LinearGradient(colors: [Color(hex: Onyx.goldHi), Color(hex: Onyx.goldLo)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
    static let checkGlow = Color(hex: Onyx.gold, alpha: 0.45)

    // Bottom bar fill (near-black wash).
    static let barFill = Color(hex: Onyx.bg0, alpha: 0.55)
}

// MARK: - Checkbox states

/// Tri-state selection for `GlassCheckbox`: `.mixed` marks a container whose
/// children are only partially selected (rendered as a minus glyph).
enum CheckState { case off, mixed, on }

// MARK: - Status pill tones

enum PillTone {
    case good, warn, blue, red

    var text: Color {
        switch self {
        case .good: return Color(hex: 0x88D6A0)
        case .warn: return Color(hex: 0xE6B478)
        // `.blue` is the app's neutral count/size tone — recolored to the
        // Onyx champagne so neutral chips match the brand instead of reading
        // blue-violet.
        case .blue: return Color(hex: Onyx.gold)
        case .red:  return Color(hex: 0xE58C86)
        }
    }

    var fill: Color {
        switch self {
        case .good: return Color(hex: 0x5FE096, alpha: 0.13)
        case .warn: return Color(hex: 0xE0A45A, alpha: 0.14)
        case .blue: return Color(hex: Onyx.gold, alpha: 0.14)
        case .red:  return Color(hex: 0xE0685C, alpha: 0.15)
        }
    }
}

// MARK: - Frosted glass surface

/// Translucent cream glass per the mockup (`.glass`): cream 0.045 fill, cream
/// 0.09 hairline. Deliberately NOT a system material — materials sample the
/// backdrop, which renders black in offscreen snapshots and hides the stage.
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
