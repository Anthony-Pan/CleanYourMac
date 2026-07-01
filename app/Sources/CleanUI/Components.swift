import SwiftUI
import AppKit
import CleanCore

// MARK: - Per-category visual style (vivid gradients on the violet stage)

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

// MARK: - Big grid card (tap anywhere → open detail screen)

struct CategoryGridCard: View {
    let group: ScanResultGroup
    let model: ScanViewModel
    let onOpen: () -> Void

    @State private var hover = false
    private var style: CategoryStyle { .forID(group.category.id) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(style.gradient)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center))
        }
        .overlay(alignment: .topLeading) {
            Text(group.category.nameEN)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.95))
                .padding(20)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: style.symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
                .padding(20)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ByteFormat.human(group.totalBytes))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(group.items.count) items · tap to review")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(20)
        }
        .overlay(alignment: .bottomTrailing) {
            Button { model.toggleCategory(group) } label: {
                Image(systemName: masterIcon)
                    .font(.system(size: 25))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 4)
            }
            .buttonStyle(.plain)
            .padding(18)
        }
        .frame(height: 176)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: style.glow.opacity(0.45), radius: hover ? 26 : 16, y: hover ? 14 : 9)
        .scaleEffect(hover ? 1.015 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture { onOpen() }
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }

    private var masterIcon: String {
        switch model.categoryState(group) {
        case .all:  return "checkmark.circle.fill"
        case .some: return "minus.circle.fill"
        case .none: return "circle"
        }
    }
}

// MARK: - The circular gauge (used for scanning / done states)

struct ReclaimGauge: View {
    let bytes: Int64
    let scanning: Bool
    let done: Bool

    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Palette.accent.opacity(0.34), .clear],
                                     center: .center, startRadius: 30, endRadius: 150))
                .scaleEffect(pulse ? 1.08 : 0.9)
                .opacity(scanning ? 1 : 0.5)

            Circle().stroke(.white.opacity(0.08), lineWidth: 15)

            Circle()
                .trim(from: 0, to: scanning ? 0.22 : 1)
                .stroke(Palette.accentRing, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .shadow(color: Palette.accent.opacity(0.55), radius: 14)

            center
        }
        .frame(width: 214, height: 214)
        .onAppear { start() }
        .onChange(of: scanning) { _, _ in start() }
    }

    @ViewBuilder private var center: some View {
        VStack(spacing: 3) {
            Text(ByteFormat.human(bytes))
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
            Text(scanning ? "scanning…" : (done ? "cleaned" : "reclaimable"))
                .font(.callout)
                .foregroundStyle(Palette.muted)
        }
    }

    private func start() {
        if scanning {
            spin = false
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
        } else {
            withAnimation(.easeOut(duration: 0.3)) { spin = false }
        }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { pulse = true }
    }
}

// MARK: - One file row (used in the detail screen)

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

// MARK: - Roadmap placeholder

struct ComingSoonView: View {
    let title: String
    let symbol: String

    var body: some View {
        ZStack {
            StageBackground()
            VStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 46))
                    .foregroundStyle(.white.opacity(0.4))
                Text(title).font(.title2.bold()).foregroundStyle(Palette.ink)
                Text("Coming soon.").foregroundStyle(Palette.muted)
            }
        }
    }
}
