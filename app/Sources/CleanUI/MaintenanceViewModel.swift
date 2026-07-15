import Foundation
import Observation
import CleanCore

/// Drives the Maintenance screen: a fixed checklist of safe, no-sudo system
/// refresh tasks (from `MaintenanceTask.registry`) run sequentially in
/// registry order.
@MainActor
@Observable
final class MaintenanceViewModel {
    enum Phase: Equatable {
        case ready, running, done
    }

    /// Per-task progress while (and after) a run.
    enum TaskState: Equatable {
        case waiting
        case active
        case succeeded(MaintenanceResult)
        case failed(MaintenanceResult)
    }

    private(set) var phase: Phase = .ready
    /// The fixed registry, in run order. Never mutated.
    let tasks: [MaintenanceTask]
    /// Task IDs currently ticked for running. All on by default.
    private(set) var enabled: Set<String>
    /// State of each task in the current/last run, keyed by task ID. Tasks not
    /// part of the run have no entry.
    private(set) var states: [String: TaskState] = [:]

    private let runner = MaintenanceRunner()
    private var runTask: Task<Void, Never>?

    init() {
        tasks = MaintenanceTask.registry
        enabled = Set(MaintenanceTask.registry.map(\.id))
    }

    /// Preloaded done-state for design previews — zero disk or process access.
    /// Each result maps onto its registry task; tasks without a result render
    /// as unselected.
    init(mockResults: [MaintenanceResult]) {
        tasks = MaintenanceTask.registry
        enabled = Set(mockResults.map(\.taskID))
        for result in mockResults {
            states[result.taskID] = result.succeeded ? .succeeded(result) : .failed(result)
        }
        phase = .done
    }

    // MARK: - Selection

    func isEnabled(_ id: String) -> Bool { enabled.contains(id) }

    func toggle(_ id: String) {
        guard phase == .ready else { return }
        if enabled.contains(id) { enabled.remove(id) } else { enabled.insert(id) }
    }

    var enabledTasks: [MaintenanceTask] {
        tasks.filter { enabled.contains($0.id) }
    }

    var enabledCount: Int { enabled.count }

    /// Warnings for the current selection, in registry order — the substance of
    /// the confirmation dialog.
    var selectedWarnings: [String] {
        enabledTasks.compactMap(\.warning)
    }

    // MARK: - Run state

    func state(of id: String) -> TaskState? { states[id] }

    /// The result behind a finished task, if any.
    func result(of id: String) -> MaintenanceResult? {
        switch states[id] {
        case .succeeded(let result), .failed(let result): return result
        default: return nil
        }
    }

    var succeededCount: Int {
        states.values.filter { if case .succeeded = $0 { return true } else { return false } }.count
    }

    var failedCount: Int {
        states.values.filter { if case .failed = $0 { return true } else { return false } }.count
    }

    var completedCount: Int { succeededCount + failedCount }

    /// Name of the task currently executing, for the running-phase status line.
    var activeTaskName: String? {
        tasks.first { states[$0.id] == .active }?.name
    }

    // MARK: - Run / reset

    func runSelected() {
        guard phase != .running, !enabled.isEmpty else { return }
        runTask?.cancel()
        runTask = Task { await runAll() }
    }

    /// Back to the checklist (selection kept) so a re-run goes through the
    /// normal confirmation — Finder/Dock restarts should never fire silently.
    func reset() {
        guard phase == .done else { return }
        states = [:]
        phase = .ready
    }

    private func runAll() async {
        phase = .running
        states = [:]
        let toRun = enabledTasks
        for task in toRun { states[task.id] = .waiting }

        let runner = runner
        for task in toRun {
            states[task.id] = .active
            // `run` hops off the main actor internally; the await keeps the UI live.
            let result = await runner.run(task)
            states[task.id] = result.succeeded ? .succeeded(result) : .failed(result)
        }
        phase = .done
    }
}
