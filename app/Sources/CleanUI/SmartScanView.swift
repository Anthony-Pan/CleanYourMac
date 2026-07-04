import SwiftUI
import CleanCore

struct SmartScanView: View {
    let model: ScanViewModel
    @State private var showConfirm = false

    init(model: ScanViewModel) { self.model = model }

    var body: some View {
        ZStack {
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
        VStack(spacing: 0) {
            Spacer()

            HeroBlob(theme: .magenta, symbol: "sparkles")

            Text("Smart Scan")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 26)

            Text("Find caches, logs and developer junk you can safely reclaim.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 8)

            Spacer()

            CircleActionButton(title: "Scan", theme: .magenta) { model.startScan() }
        }
        .padding(.bottom, 36)
    }

    // MARK: - Scanning (live discovery)

    private var scanningView: some View {
        VStack(spacing: 0) {
            Spacer()

            HeroBlob(theme: .magenta, symbol: "sparkles", animating: true)

            Text("Scanning…")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 24)

            if !model.currentLocation.isEmpty {
                Text(model.currentLocation)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 460)
                    .padding(.top, 8)
                    .contentTransition(.opacity)
            }

            Text("\(model.foundCount) items · \(ByteFormat.human(model.scannedBytes)) found")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.muted)
                .padding(.top, 4)

            VStack(spacing: 5) {
                ForEach(model.recentFinds.reversed()) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(item.url.lastPathComponent)
                            .foregroundStyle(.white.opacity(0.85))
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
            .frame(width: 460, height: 120, alignment: .top)
            .animation(.snappy, value: model.recentFinds)
            .padding(.top, 18)

            Spacer()

            CircleActionButton(title: "Stop", theme: .magenta, ring: .progress) { model.cancelScan() }
        }
        .padding(.bottom, 36)
    }

    // MARK: - Cleaning

    private var cleaningView: some View {
        VStack(spacing: 0) {
            Spacer()

            HeroBlob(theme: .magenta, symbol: "sparkles", animating: true)

            Text("Moving to Trash…")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 24)

            Spacer()

            CircleActionButton(title: "Cleaning", theme: .magenta, ring: .progress, disabled: true) {}
        }
        .padding(.bottom, 36)
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.45), radius: 18)

            Text("All clean!")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 18)

            Text("Freed \(ByteFormat.human(model.lastReport?.freedBytes ?? 0)) · moved \(model.lastReport?.trashed.count ?? 0) items to Trash")
                .foregroundStyle(Palette.muted)
                .padding(.top, 6)

            Spacer()

            CircleActionButton(title: "Scan Again", theme: .magenta) { model.startScan() }
        }
        .padding(.bottom, 36)
    }

    // MARK: - Grid

    private var gridView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("SMART SCAN")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.6)
                    .foregroundStyle(Palette.muted)
                Text("\(ByteFormat.human(model.selectedBytes)) to clean up")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(model.selectedItemCount) items across \(model.groups.count) categories · everything goes to the Trash")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.top, 46)
            .padding(.bottom, 22)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(model.groups) { group in
                        CategoryGridCard(group: group, model: model) {
                            withAnimation(.snappy) { model.openedCategoryID = group.id }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
            }

            VStack(spacing: 10) {
                Text("\(model.selectedItemCount) items · \(ByteFormat.human(model.selectedBytes)) selected")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))

                CircleActionButton(title: "Clean", theme: .magenta,
                                   disabled: model.selectedItemCount == 0) { showConfirm = true }
            }
            .padding(.bottom, 24)
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
                GlassPill(title: "Smart Scan", systemImage: "chevron.left", action: onBack)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 48)
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
                GlassPill(title: model.categoryState(group) == .all ? "Deselect All" : "Select All") {
                    model.toggleCategory(group)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                        ItemRow(item: item,
                                selected: model.isItemSelected(item.id),
                                color: .white) {
                            model.toggleItem(item.id)
                        }
                        if index < group.items.count - 1 {
                            Rectangle().fill(Palette.hair).frame(height: 1).padding(.leading, 44)
                        }
                    }
                }
                .padding(.vertical, 6)
                .glassCard(radius: 16)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            HStack {
                Text("\(model.selectedCount(in: group)) selected · \(ByteFormat.human(selectedBytesInGroup))")
                    .font(.subheadline).foregroundStyle(Palette.ink)
                Spacer()
                GlassPill(title: "Done", prominent: true, action: onBack)
            }
            .padding(16)
            .overlay(alignment: .top) { Rectangle().fill(Palette.hair).frame(height: 1) }
        }
    }

    private var selectedBytesInGroup: Int64 {
        group.items.reduce(0) { $0 + (model.isItemSelected($1.id) ? $1.sizeBytes : 0) }
    }
}
