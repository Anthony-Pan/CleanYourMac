import XCTest
@testable import CleanCore

/// Registry invariants + runner behavior. The runner tests only ever launch
/// harmless standard tools (/usr/bin/true, /bin/echo, /bin/sleep, /bin/cat on
/// a sandboxed temp file) — never the real killall/lsregister/qlmanage.
final class MaintenanceTests: XCTestCase {
    // MARK: - Registry invariants

    func test_registryHasUniqueIDs() {
        let ids = MaintenanceTask.registry.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "task ids must be unique")
    }

    func test_registryHasExpectedTasksInOrder() {
        XCTAssertEqual(MaintenanceTask.registry.map(\.id), [
            "flush-dns",
            "rebuild-launchservices",
            "reset-quicklook",
            "restart-finder",
            "restart-dock",
        ])
    }

    func test_registryExecutablePathsAreAbsolute() {
        for task in MaintenanceTask.registry {
            XCTAssertTrue(task.executablePath.hasPrefix("/"),
                          "\(task.id): executable path must be absolute, got \(task.executablePath)")
        }
    }

    func test_registryArgumentsAreFixedAndNonEmpty() {
        for task in MaintenanceTask.registry {
            XCTAssertFalse(task.arguments.isEmpty, "\(task.id): arguments must be a fixed non-empty list")
            for argument in task.arguments {
                XCTAssertFalse(argument.isEmpty, "\(task.id): no empty argument literals")
            }
        }
    }

    func test_registryNamesAndDetailsPresent() {
        for task in MaintenanceTask.registry {
            XCTAssertFalse(task.name.isEmpty, "\(task.id): name required")
            XCTAssertFalse(task.detail.isEmpty, "\(task.id): detail required")
        }
    }

    func test_registryDisruptiveTasksCarryWarnings() {
        let warned = MaintenanceTask.registry.filter { $0.warning != nil }.map(\.id)
        XCTAssertEqual(warned, ["restart-finder", "restart-dock"],
                       "exactly the Finder/Dock restarts must warn the user")
    }

    func test_registryNeverInvokesAShell() {
        for task in MaintenanceTask.registry {
            for shell in ["/bin/sh", "/bin/bash", "/bin/zsh", "/usr/bin/env"] {
                XCTAssertNotEqual(task.executablePath, shell, "\(task.id): must not run through a shell")
            }
        }
    }

    // MARK: - Runner

    private func task(_ id: String, _ path: String, _ args: [String] = []) -> MaintenanceTask {
        MaintenanceTask(id: id, name: id, detail: "test", executablePath: path, arguments: args)
    }

    func test_runnerSucceedsForZeroExit() async {
        let result = await MaintenanceRunner().run(task("t-true", "/usr/bin/true"))
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.taskID, "t-true")
        XCTAssertGreaterThanOrEqual(result.duration, 0)
    }

    func test_runnerFailsForNonZeroExit() async {
        let result = await MaintenanceRunner().run(task("t-false", "/usr/bin/false"))
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertFalse(result.succeeded)
    }

    func test_runnerFailsGracefullyForMissingExecutable() async {
        let path = "/nonexistent-\(UUID().uuidString)/tool"
        let result = await MaintenanceRunner().run(task("t-missing", path))
        XCTAssertFalse(result.succeeded)
        XCTAssertNil(result.exitCode, "a task that never launched has no exit code")
        XCTAssertTrue(result.output.contains(path), "output should say what could not be found")
    }

    func test_runnerCapturesStandardOutput() async {
        let result = await MaintenanceRunner().run(task("t-echo", "/bin/echo", ["hello"]))
        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.output.contains("hello"), "stdout must be captured, got: \(result.output)")
    }

    func test_runnerTruncatesLongOutput() async throws {
        // ~10 KB through /bin/cat on a sandboxed temp file — no shell involved.
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cym-maint-\(UUID().uuidString).txt")
        let blob = String(repeating: "0123456789abcdef", count: 640)
        try blob.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let result = await MaintenanceRunner().run(task("t-cat", "/bin/cat", [file.path]))
        XCTAssertTrue(result.succeeded)
        // Truncated payload plus at most the "…" marker.
        XCTAssertLessThanOrEqual(result.output.utf8.count,
                                 MaintenanceRunner.maxOutputBytes + "…".utf8.count)
        XCTAssertTrue(result.output.hasSuffix("…"), "clipped output must be marked")
    }

    func test_runnerTimeoutTerminatesProcessAndFails() async {
        let started = Date()
        let result = await MaintenanceRunner(timeout: 0.5).run(task("t-sleep", "/bin/sleep", ["30"]))
        XCTAssertFalse(result.succeeded)
        XCTAssertNil(result.exitCode, "a timed-out task reports no exit code")
        XCTAssertTrue(result.output.contains("timed out"), "output should mention the timeout")
        XCTAssertLessThan(Date().timeIntervalSince(started), 10,
                          "the process must be terminated, not waited on for 30s")
    }
}
