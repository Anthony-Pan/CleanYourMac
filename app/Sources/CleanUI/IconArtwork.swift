import AppKit
import SwiftUI

/// The app icon artwork. The master art (AI-generated crystal sparkle over a
/// teal→blue→violet gradient, full-bleed square) lives at Resources/IconArt.png
/// and is clipped to macOS's icon-grid squircle here. Rendered to a 1024×1024
/// PNG by the `snapshot icon` tool, then turned into an .icns at package time.
/// Falls back to the original gradient+sparkles drawing if the resource is
/// missing, so `snapshot icon` never silently produces an empty image.
public struct IconArtwork: View {
    private static let masterArt: NSImage? = Bundle.module
        .url(forResource: "IconArt", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }

    private static let squircle = RoundedRectangle(cornerRadius: 184, style: .continuous)

    public init() {}

    public var body: some View {
        ZStack {
            if let art = Self.masterArt {
                Image(nsImage: art)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 824, height: 824)
                    .clipShape(Self.squircle)
            } else {
                fallbackGradient
            }
        }
        .overlay(
            Self.squircle
                .stroke(.white.opacity(0.18), lineWidth: 3)
                .frame(width: 824, height: 824)
        )
        .shadow(color: .black.opacity(0.22), radius: 24, y: 14)
        .frame(width: 1024, height: 1024)
    }

    /// Pre-0.2 programmatic artwork, kept as a fallback and drawn to match the
    /// in-app gradient ring.
    private var fallbackGradient: some View {
        ZStack {
            Self.squircle
                .fill(
                    LinearGradient(
                        colors: [.teal, .blue, .indigo, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 824, height: 824)

            Image(systemName: "sparkles")
                .font(.system(size: 400, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
        }
    }
}
