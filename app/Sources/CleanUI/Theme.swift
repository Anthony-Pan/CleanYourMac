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

// MARK: - Module themes

/// One module's signature colors, CleanMyMac-5 style: a full-bleed gradient
/// stage (deep edges, bright glow center) plus an accent for its primary
/// circular action button.
struct ModuleTheme: Equatable {
    let deep: Color      // darkest, outer edges of the stage
    let mid: Color       // upper-body tint of the stage
    let glow: Color      // bright radial center
    let accent: Color    // action-button fill
    let accentHi: Color  // lighter accent, gradient top

    var accentGradient: LinearGradient {
        LinearGradient(colors: [accentHi, accent], startPoint: .top, endPoint: .bottom)
    }

    /// Smart Scan — magenta on deep purple.
    static let magenta = ModuleTheme(
        deep: Color(hex: 0x24072F), mid: Color(hex: 0x7A1B8F),
        glow: Color(hex: 0xDE47BE), accent: Color(hex: 0xC91FB5), accentHi: Color(hex: 0xEF5AD6))

    /// Uninstaller — indigo on deep navy.
    static let indigo = ModuleTheme(
        deep: Color(hex: 0x0D0A33), mid: Color(hex: 0x322788),
        glow: Color(hex: 0x7263F2), accent: Color(hex: 0x5D49F0), accentHi: Color(hex: 0x8672FF))

    /// Large & Old Files — teal on deep pine.
    static let teal = ModuleTheme(
        deep: Color(hex: 0x032220), mid: Color(hex: 0x0C574D),
        glow: Color(hex: 0x2FB9A4), accent: Color(hex: 0x0FA893), accentHi: Color(hex: 0x36CDB4))

    /// Privacy — azure on deep navy.
    static let blue = ModuleTheme(
        deep: Color(hex: 0x051430), mid: Color(hex: 0x0F3A78),
        glow: Color(hex: 0x3E8BE8), accent: Color(hex: 0x2374E1), accentHi: Color(hex: 0x59A5FF))
}

// MARK: - Shared text & chrome colors

enum Palette {
    static let ink = Color.white
    static let ink2 = Color.white.opacity(0.82)
    static let muted = Color.white.opacity(0.58)
    static let faint = Color.white.opacity(0.36)
    static let hair = Color.white.opacity(0.10)
    static let warn = Color(hex: 0xFFD48A)

    static let glassBorder = Color.white.opacity(0.16)
    static let glassBorderFocus = Color.white.opacity(0.34)
    static let glassGradient = LinearGradient(stops: [
        .init(color: .white.opacity(0.13), location: 0.0),
        .init(color: .white.opacity(0.06), location: 0.55),
        .init(color: .white.opacity(0.03), location: 1.0),
    ], startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Module stage background

/// The full-bleed gradient stage behind a module: deep edges, a bright glow
/// slightly above center, a soft vignette, and drifting particles. Drawn once
/// by `RootView`; individual screens never draw their own background.
struct ModuleBackground: View {
    let theme: ModuleTheme
    /// Brighter, breathing glow while the module is scanning or cleaning.
    var active: Bool = false

    @State private var pulse = false

    var body: some View {
        ZStack {
            theme.deep

            LinearGradient(stops: [
                .init(color: theme.mid.opacity(0.90), location: 0.0),
                .init(color: theme.mid.opacity(0.35), location: 0.55),
                .init(color: .clear, location: 1.0),
            ], startPoint: .top, endPoint: .bottom)

            RadialGradient(
                colors: [theme.glow.opacity(active ? 0.80 : 0.58), theme.glow.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.38),
                startRadius: 30,
                endRadius: 660
            )
            .scaleEffect(pulse ? 1.05 : 0.96)
            .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: pulse)

            ParticleField(animating: active)

            RadialGradient(colors: [.clear, .black.opacity(0.42)],
                           center: UnitPoint(x: 0.5, y: 0.45),
                           startRadius: 320, endRadius: 940)
        }
        .ignoresSafeArea()
        .onAppear { pulse = true }
    }
}

// MARK: - Frosted glass surface

struct GlassCard: ViewModifier {
    var radius: CGFloat = 16
    var focused: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.glassGradient)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(focused ? Palette.glassBorderFocus : Palette.glassBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 20, y: 12)
    }
}

extension View {
    func glassCard(radius: CGFloat = 16, focused: Bool = false) -> some View {
        modifier(GlassCard(radius: radius, focused: focused))
    }
}

// MARK: - Lightweight particle field

private struct StageParticle {
    let x: Double, phase: Double, speed: Double
    let sway: Double, size: Double, baseOpacity: Double, twinkle: Double
}

struct ParticleField: View {
    var animating: Bool
    private let particles: [StageParticle]

    init(animating: Bool, count: Int = 34) {
        self.animating = animating
        var rng = SystemRandomNumberGenerator()
        particles = (0..<count).map { _ in
            StageParticle(
                x: .random(in: 0...1, using: &rng),
                phase: .random(in: 0...1, using: &rng),
                speed: .random(in: 0.008...0.032, using: &rng),
                sway: .random(in: 0.2...1.1, using: &rng),
                size: .random(in: 0.9...2.2, using: &rng),
                baseOpacity: .random(in: 0.03...0.13, using: &rng),
                twinkle: .random(in: 0.3...1.4, using: &rng)
            )
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animating)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for p in particles {
                    let frac = (p.phase + t * p.speed).truncatingRemainder(dividingBy: 1)
                    let y = size.height * (1 - frac)
                    let x = p.x * size.width + sin(t * p.sway + p.phase * 6.28) * 10
                    let twinkle = 0.5 + 0.5 * sin(t * p.twinkle + p.phase * 6.28)
                    let opacity = p.baseOpacity * (animating ? 1.0 : 0.55) * twinkle
                    let r = p.size
                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
