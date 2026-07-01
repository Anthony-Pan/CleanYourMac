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

/// Palette: CleanMyMac-style deep violet stage with a bright aqua accent and
/// vivid per-category card gradients.
enum Palette {
    static let bg = Color(hex: 0x140A28)
    static let purpleTop = Color(hex: 0x2E1758)
    static let purpleGlow = Color(hex: 0x6A34C8)

    static let ink = Color(hex: 0xF3F1FA)
    static let ink2 = Color(hex: 0xDBD6EC)
    static let muted = Color(hex: 0x9A93B8)
    static let hair = Color.white.opacity(0.08)

    static let accent = Color(hex: 0x00F5D4)          // aqua
    static let blue = Color(hex: 0x2442FF)
    static let champagne = Color(hex: 0xF4D28A)
    static let mint = Color(hex: 0x9CFFDF)

    static let accentColors = [Color(hex: 0xE7FFF9), Color(hex: 0x00F5D4), Color(hex: 0x61A8FF)]
    static let accentRing = AngularGradient(gradient: Gradient(colors: accentColors + [accentColors[0]]), center: .center)
    static let accentLinear = LinearGradient(colors: accentColors, startPoint: .topLeading, endPoint: .bottomTrailing)

    static let glassGradient = LinearGradient(stops: [
        .init(color: Color.white.opacity(0.10), location: 0.0),
        .init(color: Color.white.opacity(0.04), location: 0.5),
        .init(color: Color.black.opacity(0.10), location: 1.0),
    ], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let glassBorder = Color.white.opacity(0.11)
    static let glassBorderFocus = Color(hex: 0x00F5D4, alpha: 0.35)
}

// MARK: - Frosted glass surface

struct GlassCard: ViewModifier {
    var radius: CGFloat = 18
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
            .shadow(color: .black.opacity(0.30), radius: 24, y: 14)
    }
}

extension View {
    func glassCard(radius: CGFloat = 18, focused: Bool = false) -> some View {
        modifier(GlassCard(radius: radius, focused: focused))
    }
}

// MARK: - Stage background (deep violet + spotlight + particles + vignette)

struct StageBackground: View {
    var glow: Bool = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.purpleTop, Palette.bg],
                           startPoint: .top, endPoint: .bottom)

            RadialGradient(
                colors: [Palette.purpleGlow.opacity(glow ? 0.60 : 0.42), .clear],
                center: UnitPoint(x: 0.5, y: 0.10),
                startRadius: 40,
                endRadius: 780
            )
            .scaleEffect(pulse ? 1.05 : 0.95)
            .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: pulse)

            ParticleField(animating: glow)

            RadialGradient(colors: [.clear, .black.opacity(0.45)],
                           center: .center, startRadius: 240, endRadius: 720)
        }
        .ignoresSafeArea()
        .onAppear { pulse = true }
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

    init(animating: Bool, count: Int = 40) {
        self.animating = animating
        var rng = SystemRandomNumberGenerator()
        particles = (0..<count).map { _ in
            StageParticle(
                x: .random(in: 0...1, using: &rng),
                phase: .random(in: 0...1, using: &rng),
                speed: .random(in: 0.008...0.036, using: &rng),
                sway: .random(in: 0.2...1.1, using: &rng),
                size: .random(in: 1.0...2.4, using: &rng),
                baseOpacity: .random(in: 0.03...0.16, using: &rng),
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
