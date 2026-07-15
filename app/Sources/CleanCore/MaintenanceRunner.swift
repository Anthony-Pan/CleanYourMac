import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Result

/// Outcome of one maintenance task run.
public struct MaintenanceResult: Sendable, Equatable {
    public let taskID: String
    /// The process's exit code, or `nil` when it never produced one (could not
    /// launch, or was terminated on timeout).
    public let exitCode: Int32?
    public let succeeded: Bool
    /// Combined stdout + stderr, truncated to `MaintenanceRunner.maxOutputBytes`.
    public let output: String
    public let duration: TimeInterval

    public init(taskID: String, exitCode: Int32?, succeeded: Bool, output: String, duration: TimeInterval) {
        self.taskID = taskID
        self.exitCode = exitCode
        self.succeeded = succeeded
        self.output = output
        self.duration = duration
    }
}

// MARK: - Runner

/// Executes `MaintenanceTask`s. Never a shell: each task launches via
/// `Process.executableURL` with its fixed argument array, so nothing the user
/// (or a scan result) provides can ever reach a command line. Usable off the
/// main actor — the blocking wait happens on a Dispatch queue, not on the
/// cooperative thread pool.
public struct MaintenanceRunner: Sendable {
    /// Output kept per task (~2 KB) — enough to diagnose a failure without
    /// letting a chatty tool bloat memory or the UI.
    public static let maxOutputBytes = 2048

    /// Wall-clock deadline after which the process is terminated and the task
    /// marked failed. Injectable so tests don't wait two minutes.
    public let timeout: TimeInterval

    public init(timeout: TimeInterval = 120) {
        self.timeout = timeout
    }

    public func run(_ task: MaintenanceTask) async -> MaintenanceResult {
        let timeout = timeout
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.runBlocking(task, timeout: timeout))
            }
        }
    }

    // MARK: - Blocking core (runs on a Dispatch queue)

    private static func runBlocking(_ task: MaintenanceTask, timeout: TimeInterval) -> MaintenanceResult {
        let start = Date()

        func failed(_ message: String, exitCode: Int32? = nil) -> MaintenanceResult {
            MaintenanceResult(taskID: task.id, exitCode: exitCode, succeeded: false,
                              output: message, duration: Date().timeIntervalSince(start))
        }

        guard FileManager.default.fileExists(atPath: task.executablePath) else {
            return failed("Tool not found: \(task.executablePath)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: task.executablePath)
        process.arguments = task.arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return failed("Could not launch \(task.executablePath): \(error.localizedDescription)")
        }

        // Drain the pipe off-thread and signal on EOF. EOF requires every write
        // end to close, so waiting on the drain (not just process exit) bounds
        // both a chatty tool and a stuck child holding the pipe open — the same
        // hard-deadline approach as ProcessCommandRunner.
        let drained = DispatchSemaphore(value: 0)
        let buffer = OutputBuffer()
        DispatchQueue(label: "com.cleanyourmac.maintenance-runner.read").async {
            buffer.data = pipe.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }

        let timedOut = drained.wait(timeout: .now() + timeout) != .success
        if timedOut {
            process.terminate()                              // SIGTERM
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)     // escalate
            }
            try? pipe.fileHandleForReading.close()           // unblock the drain
            _ = drained.wait(timeout: .now() + 1)
        }
        process.waitUntilExit()

        let duration = Date().timeIntervalSince(start)
        var output = truncated(buffer.data ?? Data())

        if timedOut {
            let note = "[timed out after \(Int(timeout))s]"
            output = output.isEmpty ? note : "\(output)\n\(note)"
            return MaintenanceResult(taskID: task.id, exitCode: nil, succeeded: false,
                                     output: output, duration: duration)
        }

        let code = process.terminationStatus
        return MaintenanceResult(taskID: task.id, exitCode: code, succeeded: code == 0,
                                 output: output, duration: duration)
    }

    /// Lossy-decodes at most `maxOutputBytes` of combined output, marking the cut.
    private static func truncated(_ data: Data) -> String {
        let clipped = data.count > maxOutputBytes
        let text = String(decoding: data.prefix(maxOutputBytes), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clipped ? text + "…" : text
    }
}

/// Reference box so the drain thread's result survives the closure boundary.
private final class OutputBuffer: @unchecked Sendable {
    var data: Data?
}
