import SwiftUI

/// The app icon artwork, drawn to match the in-app gradient ring. Rendered to a
/// 1024×1024 PNG by the `snapshot icon` tool, then turned into an .icns at
/// package time. The rounded square is inset to sit on macOS's icon grid.
public struct IconArtwork: View {
    public init() {}

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 184, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.teal, .blue, .indigo, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 824, height: 824)
                .overlay(
                    RoundedRectangle(cornerRadius: 184, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 3)
                        .frame(width: 824, height: 824)
                )
                .shadow(color: .black.opacity(0.22), radius: 24, y: 14)

            Image(systemName: "sparkles")
                .font(.system(size: 400, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
        }
        .frame(width: 1024, height: 1024)
    }
}
