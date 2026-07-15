import SwiftUI
import CleanCore

/// The Optimization module: a read-only review of what launches at startup —
/// user launch agents plus system-wide third-party agents and daemons.
/// Nothing is modified; the screen gives visibility, reveal-in-Finder, and a
/// shortcut to the Login Items system settings.
struct OptimizationView: View {
    let model: OptimizationViewModel

    init(model: OptimizationViewModel) { self.model = model }

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .idle:
                idleView
            case .scanning:
                scanningView
            case .results:
                resultsView
            }
        }
        .navigationTitle("Optimization")
    }

    // MARK: - Idle (start screen with a Review button)

    private var idleView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Optimization") { StatusPill(text: "Ready", tone: .blue) }

            Spacer()

            Orb(size: 230)

            Text("See what launches at startup")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 6)

            Text("Launch agents and daemons start in the background when your Mac boots or you log in — too many can slow login and keep running unseen.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.sub)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .padding(.top, 8)

            CTACircle(title: "Review") { model.review() }
                .padding(.top, 30)

            Spacer()

            Text("Read-only — CleanYourMac never changes startup items.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.tiny)
                .padding(.bottom, 26)
        }
    }

    // MARK: - Scanning (near-instant, kept for consistency)

    private var scanningView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Optimization") { StatusPill(text: "Reviewing…", tone: .blue) }

            Spacer()

            Orb(size: 230, animating: true)

            Text("Checking startup items…")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 6)

            Text("Reading launch agents and daemons — nothing is modified.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.sub)
                .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            TopBar(title: "Optimization") {
                if model.unreadableCount > 0 {
                    StatusPill(text: "\(model.unreadableCount) unreadable", tone: .warn)
                }
                StatusPill(text: "\(model.thirdPartyCount) third-party",
                           tone: model.thirdPartyCount == 0 ? .good : .blue)
                appleToggle
                GhostButton(title: "Login Items Settings…") { model.openLoginItemsSettings() }
            }

            if model.sections.isEmpty {
                emptyState
            } else {
                sectionList
            }

            BottomBar {
                Text("Read-only — CleanYourMac never changes startup items. Remove one via the app that installed it, or delete its .plist in Finder.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)
                    .frame(maxWidth: 560, alignment: .leading)

                Spacer()

                GhostButton(title: "Review Again") { model.review() }
            }
        }
    }

    /// Small capsule toggle for Apple-owned items (hidden by default).
    private var appleToggle: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { model.showApple.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: model.showApple ? "eye" : "eye.slash")
                    .font(.system(size: 10, weight: .semibold))
                Text(model.showApple
                     ? "Hide Apple items"
                     : "Show Apple items (\(model.appleCount))")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(model.showApple ? Palette.ink : Palette.sub)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(model.showApple ? 0.12 : 0.06)))
            .overlay(Capsule().strokeBorder(Palette.glassBorder, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(model.showApple
              ? "Hide items macOS itself installs"
              : "Also show items macOS itself installs")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.45), radius: 18)

            Text("No third-party startup items")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 18)

            StatusPill(text: "Nothing launches behind your back", tone: .good)
                .padding(.top, 10)

            if !model.showApple && model.appleCount > 0 {
                Text("\(model.appleCount) Apple-owned items are hidden — part of macOS itself.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grouped sections

    private var sectionList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(model.sections) { sectionCard($0) }

                if !model.showApple && model.appleCount > 0 {
                    Text("\(model.appleCount) Apple-owned items hidden")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tiny)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionCard(_ section: OptimizationViewModel.Section) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(section.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)

                countPill(section.items.count)

                Spacer()

                Text(section.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)
            }
            .padding(.bottom, 6)

            ForEach(section.items) { itemRow($0) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassCard(radius: 16)
    }

    private func countPill(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Palette.ink2)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(.white.opacity(0.10)))
    }

    // MARK: - Item rows

    private func itemRow(_ item: StartupItem) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor(item))
                .frame(width: 7, height: 7)
                .shadow(color: statusColor(item).opacity(0.5), radius: 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.label)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if item.isApple {
                        TagBadge(text: "Apple", color: Palette.sub)
                    }
                }
                Text(item.executable ?? "No executable path declared")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            statusBadge(item)

            Button { model.reveal(item) } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.sub)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder private func statusBadge(_ item: StartupItem) -> some View {
        if item.disabled == true {
            TagBadge(text: "Disabled", color: Palette.sub)
        } else if item.runAtLoad == true {
            TagBadge(text: "Auto-starts", color: PillTone.good.text)
        } else if item.runAtLoad == false {
            TagBadge(text: "On demand", color: Color(hex: Onyx.gold))
        }
    }

    /// Green = auto-starts, champagne = on demand/unknown, grey = disabled.
    private func statusColor(_ item: StartupItem) -> Color {
        if item.disabled == true { return Palette.sub }
        if item.runAtLoad == true { return PillTone.good.text }
        return Color(hex: Onyx.gold)
    }
}
