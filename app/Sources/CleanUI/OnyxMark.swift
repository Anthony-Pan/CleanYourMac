import SwiftUI

/// The Onyx studio mark: an elongated octagonal gem drawn as a thin stroke with
/// no fill, rendered in `currentColor` (SwiftUI's `foregroundStyle`). Kept
/// deliberately muted at call sites so it reads as a quiet signature rather than
/// a loud logo. Public because it lives in the `CleanUI` module and may be used
/// by the app target.
public struct OnyxMark: View {
    public var lineWidth: CGFloat = 1

    public init(lineWidth: CGFloat = 1) {
        self.lineWidth = lineWidth
    }

    public var body: some View {
        GeometryReader { geo in
            let sx = geo.size.width / 24, sy = geo.size.height / 32
            // A `let` closure (not a `func`): ViewBuilder closures allow constant
            // bindings but not nested function declarations.
            let p: (CGFloat, CGFloat) -> CGPoint = { x, y in CGPoint(x: x * sx, y: y * sy) }
            ZStack {
                Path { pth in
                    pth.move(to: p(12, 1.5)); pth.addLine(to: p(20.5, 9.5)); pth.addLine(to: p(18.5, 22))
                    pth.addLine(to: p(12, 30.5)); pth.addLine(to: p(5.5, 22)); pth.addLine(to: p(3.5, 9.5)); pth.closeSubpath()
                }.stroke(style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
                Path { pth in
                    pth.move(to: p(12, 1.5)); pth.addLine(to: p(5.5, 22)); pth.move(to: p(12, 1.5)); pth.addLine(to: p(18.5, 22))
                    pth.move(to: p(3.5, 9.5)); pth.addLine(to: p(12, 30.5)); pth.move(to: p(20.5, 9.5)); pth.addLine(to: p(12, 30.5))
                }.stroke(style: StrokeStyle(lineWidth: lineWidth * 0.7, lineJoin: .round))
            }
        }
        .aspectRatio(24.0 / 32.0, contentMode: .fit)
    }
}
