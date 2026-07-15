import SwiftUI
import CleanCore

/// The Maintenance module: a fixed checklist of safe, no-sudo macOS refresh
/// tasks (flush DNS, rebuild Launch Services, …) run sequentially with live
/// per-task status.
struct MaintenanceView: View {
    let model: MaintenanceViewModel
    @State private var showConfirm = false

    init(model: MaintenanceViewModel) { self.model = model }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Maintenance") { statusPill }

            VStack(alignment: .leading, spacing: 14) {
                header

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.tasks) { task in
                            taskCard(task)
                        }
                    }
                    .padding(.bottom, 14)
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 26)
            .padding(.top, 4)

            bottomBar
        }
        .navigationTitle("Maintenance")
        .confirmationDialog(
            "Run \(model.enabledCount) maintenance \(model.enabledCount == 1 ? "task" : "tasks")?",
            isPresented: $showConfirm, titleVisibility: .visible
        ) {
            Button("Run Tasks") { model.runSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private var confirmMessage: String {
        let reassurance = "Nothing is deleted — these tasks refresh system services and caches."
        let warnings = model.selectedWarnings
        return warnings.isEmpty ? reassurance : (warnings + [reassurance]).joined(separator: " ")
    }

    // MARK: - Top bar status

    @ViewBuilder private var statusPill: some View {
        switch model.phase {
        case .ready:
            StatusPill(text: "\(model.tasks.count) tasks", tone: .blue)
        case .running:
            StatusPill(text: "Running…", tone: .blue)
        case .done:
            if model.failedCount > 0 {
                StatusPill(text: "\(model.failedCount) failed", tone: .warn)
            } else {
                StatusPill(text: "Done", tone: .good)
            }
        }
    }

    // MARK: - Header (phase summary above the checklist)

    @ViewBuilder private var header: some View {
        switch model.phase {
        case .ready:
            Text("Safe system refreshers, run in order — nothing is deleted and no password is needed.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.sub)
        case .running:
            VStack(alignment: .leading, spacing: 4) {
                Text("Task \(min(model.completedCount + 1, model.enabledCount)) of \(model.enabledCount)")
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(model.activeTaskName.map { "Running \($0)…" } ?? "Running…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.sub)
            }
        case .done:
            VStack(alignment: .leading, spacing: 4) {
                Text(model.failedCount == 0
                     ? "All tasks completed"
                     : "Completed with \(model.failedCount) failed")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(model.succeededCount) succeeded · \(model.failedCount) failed")
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(Palette.sub)
            }
        }
    }

    // MARK: - Task cards

    private func taskCard(_ task: MaintenanceTask) -> some View {
        let style = MaintenanceTaskStyle.forID(task.id)
        let state = model.state(of: task.id)
        return HStack(spacing: 12) {
            if model.phase == .ready {
                GlassCheckbox(on: model.isEnabled(task.id)) { model.toggle(task.id) }
            }

            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(style.gradient)
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: style.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white))

            VStack(alignment: .leading, spacing: 4) {
                Text(task.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)

                Text(task.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)

                if let warning = task.warning {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text(warning)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(PillTone.warn.text)
                }

                if model.phase == .done, case .failed(let result) = state {
                    failureDetail(result)
                }
            }

            Spacer()

            trailingStatus(for: state)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .glassCard(radius: 14, focused: state == .active)
        .opacity(cardOpacity(state))
    }

    /// Truncated stdout+stderr of a failed task (or its exit code when the
    /// tool printed nothing), so failures are diagnosable in place.
    private func failureDetail(_ result: MaintenanceResult) -> some View {
        let text = result.output.isEmpty
            ? "Exited with code \(result.exitCode.map(String.init) ?? "—")"
            : result.output
        return Text(text)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(Palette.tiny)
            .lineLimit(6)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.black.opacity(0.25)))
            .padding(.top, 2)
    }

    @ViewBuilder private func trailingStatus(for state: MaintenanceViewModel.TaskState?) -> some View {
        switch state {
        case .none:
            if model.phase != .ready {
                Text("—")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.sub)
            }
        case .waiting:
            Text("—")
                .font(.system(size: 13))
                .foregroundStyle(Palette.sub)
        case .active:
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("running…")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)
            }
        case .succeeded(let result):
            Text("✓ \(Self.duration(result.duration))")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color(hex: 0x7BE8A8))
        case .failed(let result):
            Text("✗ \(Self.duration(result.duration))")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(PillTone.red.text)
        }
    }

    private func cardOpacity(_ state: MaintenanceViewModel.TaskState?) -> Double {
        guard model.phase != .ready else { return 1 }
        switch state {
        case .none: return 0.45      // not part of this run
        case .waiting: return 0.6
        default: return 1
        }
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        seconds < 9.95 ? String(format: "%.1fs", seconds) : "\(Int(seconds.rounded()))s"
    }

    // MARK: - Bottom bar

    @ViewBuilder private var bottomBar: some View {
        switch model.phase {
        case .ready:
            BottomBar {
                Text("\(model.enabledCount) of \(model.tasks.count) tasks selected")
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(Palette.sub)

                Spacer()

                GradientButton(
                    title: "Run \(model.enabledCount) \(model.enabledCount == 1 ? "Task" : "Tasks")",
                    disabled: model.enabledCount == 0
                ) { showConfirm = true }
            }
        case .running:
            BottomBar {
                Text("\(model.completedCount) of \(model.enabledCount) tasks finished")
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(Palette.sub)

                Spacer()
            }
        case .done:
            BottomBar {
                Text("\(model.succeededCount) succeeded · \(model.failedCount) failed")
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(Palette.sub)

                Spacer()

                GhostButton(title: "Run Again") { model.reset() }
            }
        }
    }
}

// MARK: - Per-task icon style (private — mirrors CategoryStyle's warm palette)

private struct MaintenanceTaskStyle {
    let symbol: String
    let a: Color
    let b: Color

    var gradient: LinearGradient {
        LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func forID(_ id: String) -> MaintenanceTaskStyle {
        switch id {
        case "flush-dns":              return .init(symbol: "network", a: Color(hex: 0xD8C49A), b: Color(hex: 0xB79E72))                      // champagne
        case "rebuild-launchservices": return .init(symbol: "arrow.triangle.2.circlepath", a: Color(hex: 0xCE9A78), b: Color(hex: 0xA66B4E)) // clay
        case "reset-quicklook":        return .init(symbol: "eye.fill", a: Color(hex: 0xC79191), b: Color(hex: 0x9E6767))                    // warm rose
        case "restart-finder":         return .init(symbol: "macwindow", a: Color(hex: 0xA9AB80), b: Color(hex: 0x7B7D54))                   // olive
        case "restart-dock":           return .init(symbol: "dock.rectangle", a: Color(hex: 0x9A928A), b: Color(hex: 0x655F59))              // warm grey
        default:                       return .init(symbol: "wrench.and.screwdriver.fill", a: Color(hex: 0x9A928A), b: Color(hex: 0x655F59))
        }
    }
}
