import SwiftUI
import CleanCore

struct SmartScanView: View {
    let model: ScanViewModel
    @State private var showConfirm = false

    init(model: ScanViewModel) { self.model = model }

    private var scanning: Bool { model.phase == .scanning || model.phase == .cleaning }

    var body: some View {
        ZStack {
            StageBackground(glow: scanning)

            switch model.phase {
            case .idle:
                idleView
            case .scanning:
                scanningView
            case .cleaning:
                cleaningView
            case .done:
                doneView
            case .results:
                if let id = model.openedCategoryID, let group = model.groups.first(where: { $0.id == id }) {
                    CategoryDetailView(group: group, model: model) {
                        withAnimation(.snappy) { model.openedCategoryID = nil }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    gridView
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
        }
        .navigationTitle("Smart Scan")
    }

    // MARK: - Idle (start screen with a Scan button)

    private var idleView: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 15)
                Circle()
                    .fill(RadialGradient(colors: [Palette.accent.opacity(0.18), .clear],
                                         center: .center, startRadius: 20, endRadius: 130))
                Image(systemName: "sparkles")
                    .font(.system(size: 58))
                    .foregroundStyle(Palette.accent)
            }
            .frame(width: 214, height: 214)

            VStack(spacing: 6) {
                Text("Smart Scan")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text("Find caches, logs and developer junk you can safely reclaim.")
                    .font(.callout)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            Button { model.startScan() } label: {
                Label("Scan", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 40)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Palette.accentLinear))
                    .shadow(color: Palette.accent.opacity(0.5), radius: 16, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(40)
    }

    // MARK: - Scanning (live discovery)

    private var scanningView: some View {
        VStack(spacing: 20) {
            ReclaimGauge(bytes: model.scannedBytes, scanning: true, done: false)

            VStack(spacing: 4) {
                Text(model.currentLocation.isEmpty ? "Scanning…" : "Scanning \(model.currentLocation)…")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.opacity)
                Text("\(model.foundCount) items found")
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(Palette.muted)
            }

            VStack(spacing: 5) {
                ForEach(model.recentFinds.reversed()) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.accent.opacity(0.8))
                        Text(item.url.lastPathComponent)
                            .foregroundStyle(Palette.ink2)
                            .lineLimit(1)
                        Spacer()
                        Text(ByteFormat.human(item.sizeBytes))
                            .foregroundStyle(Palette.muted)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(width: 440, height: 120, alignment: .top)
            .animation(.snappy, value: model.recentFinds)

            Button { model.cancelScan() } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink2)
                    .padding(.horizontal, 22).padding(.vertical, 9)
                    .background(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
    }

    // MARK: - Cleaning

    private var cleaningView: some View {
        VStack(spacing: 16) {
            ReclaimGauge(bytes: model.selectedBytes, scanning: true, done: false)
            Text("Moving to Trash…").foregroundStyle(Palette.muted)
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Palette.accent)
                .shadow(color: Palette.accent.opacity(0.5), radius: 20)
            Text("All clean!")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)
            Text("Freed \(ByteFormat.human(model.lastReport?.freedBytes ?? 0)) · moved \(model.lastReport?.trashed.count ?? 0) items to Trash")
                .foregroundStyle(Palette.muted)
            Button("Scan Again") { model.startScan() }
                .controlSize(.large)
                .tint(Palette.accent)
                .padding(.top, 6)
        }
        .padding(40)
    }

    // MARK: - Grid

    private var gridView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("SMART SCAN")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.6)
                    .foregroundStyle(Palette.muted)
                Text("\(ByteFormat.human(model.selectedBytes)) to reclaim")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                Text("\(model.selectedItemCount) items across \(model.groups.count) categories")
                    .font(.callout)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.top, 46)
            .padding(.bottom, 22)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(model.groups) { group in
                        CategoryGridCard(group: group, model: model) {
                            withAnimation(.snappy) { model.openedCategoryID = group.id }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
            }

            cleanBar
        }
    }

    private var cleanBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(model.selectedItemCount) items selected")
                    .font(.subheadline).foregroundStyle(Palette.ink)
                Text("Everything goes to the Trash — recoverable")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer()
            CleanButton(size: model.selectedBytes,
                        disabled: model.selectedItemCount == 0) { showConfirm = true }
        }
        .padding(16)
        .background(Palette.bg.opacity(0.55))
        .overlay(alignment: .top) { Rectangle().fill(Palette.hair).frame(height: 1) }
        .confirmationDialog(
            "Move \(model.selectedItemCount) items (\(ByteFormat.human(model.selectedBytes))) to the Trash?",
            isPresented: $showConfirm, titleVisibility: .visible
        ) {
            Button("Move to Trash") { Task { await model.clean() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing is deleted permanently — you can restore everything from the Trash.")
        }
    }
}

// MARK: - Reusable primary button

struct CleanButton: View {
    let size: Int64
    var disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Clean \(ByteFormat.human(size))", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background(Capsule().fill(Palette.accentLinear))
                .shadow(color: Palette.accent.opacity(disabled ? 0 : 0.5), radius: 14, y: 2)
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.4 : 1)
        .disabled(disabled)
    }
}

// MARK: - Category detail screen (its own page, not an inline expander)

struct CategoryDetailView: View {
    let group: ScanResultGroup
    let model: ScanViewModel
    let onBack: () -> Void

    private var style: CategoryStyle { .forID(group.category.id) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label("Smart Scan", systemImage: "chevron.left")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Palette.ink2)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 44)
            .padding(.bottom, 10)

            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(style.gradient)
                    .frame(width: 56, height: 56)
                    .overlay(Image(systemName: style.symbol)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white))
                    .shadow(color: style.glow.opacity(0.5), radius: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.category.nameEN)
                        .font(.title2.bold())
                        .foregroundStyle(Palette.ink)
                    Text("\(model.selectedCount(in: group)) of \(group.items.count) selected · \(ByteFormat.human(group.totalBytes))")
                        .font(.callout)
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                Button {
                    model.toggleCategory(group)
                } label: {
                    Text(model.categoryState(group) == .all ? "Deselect All" : "Select All")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                        ItemRow(item: item,
                                selected: model.isItemSelected(item.id),
                                color: style.glow) {
                            model.toggleItem(item.id)
                        }
                        if index < group.items.count - 1 {
                            Rectangle().fill(Palette.hair).frame(height: 1).padding(.leading, 44)
                        }
                    }
                }
                .padding(.vertical, 6)
                .glassCard(radius: 18)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            HStack {
                Text("\(model.selectedCount(in: group)) selected · \(ByteFormat.human(selectedBytesInGroup))")
                    .font(.subheadline).foregroundStyle(Palette.ink)
                Spacer()
                Button(action: onBack) {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        .background(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Palette.bg.opacity(0.55))
            .overlay(alignment: .top) { Rectangle().fill(Palette.hair).frame(height: 1) }
        }
    }

    private var selectedBytesInGroup: Int64 {
        group.items.reduce(0) { $0 + (model.isItemSelected($1.id) ? $1.sizeBytes : 0) }
    }
}
