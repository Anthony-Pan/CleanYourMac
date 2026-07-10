import Foundation
import Network
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Privacy finding

/// One report-only observation from the privacy audit — a permission grant, an
/// exposed network service, a weak security setting, or a hygiene concern.
///
/// Deliberately carries NO file URL: a finding can never be routed into the
/// `Cleaner`, so the audit is structurally unable to delete anything. Fixing a
/// finding is always the user's own action in System Settings or Terminal.
public struct PrivacyFinding: Identifiable, Sendable, Hashable {
    /// How urgently the user should look at this. Ordered so findings can be
    /// sorted most-severe first.
    public enum Severity: Int, Sendable, Comparable, Hashable {
        case info = 0, advisory = 1, warning = 2

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// The audit area a finding belongs to.
    public enum Category: String, Sendable, Hashable {
        case permissions, networkExposure, systemSettings
        case credentialHygiene, historyHygiene
    }

    /// Stable identifier (e.g. `"tcc-screen-capture"`, `"firewall-off"`) — the
    /// same condition always produces the same id across runs.
    public let id: String
    public let severity: Severity
    public let category: Category
    /// Short headline, e.g. "Firewall is turned off".
    public let title: String
    /// What we actually observed — honest and specific, never alarmist.
    public let detail: String
    /// One sentence telling the user what to do about it.
    public let recommendation: String
    /// `x-apple.systempreferences:` deep link to the relevant settings pane,
    /// or `nil` when the fix lives outside System Settings.
    public let settingsURLString: String?
    /// Bundle identifiers involved (permissions findings); empty otherwise.
    public let apps: [String]

    public init(
        id: String,
        severity: Severity,
        category: Category,
        title: String,
        detail: String,
        recommendation: String,
        settingsURLString: String? = nil,
        apps: [String] = []
    ) {
        self.id = id
        self.severity = severity
        self.category = category
        self.title = title
        self.detail = detail
        self.recommendation = recommendation
        self.settingsURLString = settingsURLString
        self.apps = apps
    }
}

// MARK: - External-effect seams

/// Runs a system command and returns its standard output. The audit's only
/// process-spawning seam — injectable so tests never launch real tools.
public protocol CommandRunning: Sendable {
    /// Returns the command's standard output, or `nil` when the tool cannot be
    /// launched, exits non-zero, or exceeds the timeout. `launchPath` must be
    /// absolute.
    func run(_ launchPath: String, _ arguments: [String]) -> String?
}

/// Probes whether a local TCP port accepts connections. Injectable so tests
/// never open real sockets.
public protocol PortProbing: Sendable {
    /// True when 127.0.0.1:`port` accepts a TCP connection within ~1 second.
    func isOpen(_ port: UInt16) async -> Bool
}

// MARK: - Real implementations

/// Production `CommandRunning`: `Process` with a hard 5-second wall-clock
/// deadline. Standard error is discarded; a process that overruns is sent
/// SIGTERM and then SIGKILL so a hung or SIGTERM-ignoring tool can never stall
/// the audit.
public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ launchPath: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }

        // Drain stdout off-thread and signal on EOF. EOF requires every write
        // end of the pipe to close, so this bounds BOTH a chatty tool (pipe
        // buffer full) and a stuck child holding the pipe open — waiting on the
        // drain, not just process exit, is what makes the 5 s deadline hard.
        let drained = DispatchSemaphore(value: 0)
        let box = OutputBox()
        DispatchQueue(label: "com.cleanyourmac.command-runner.read").async {
            box.data = stdout.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }

        let deadline = DispatchTime.now() + 5
        guard drained.wait(timeout: deadline) == .success else {
            process.terminate()                                   // SIGTERM
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)          // escalate
            }
            try? stdout.fileHandleForReading.close()              // unblock the drain
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return box.data.flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// Reference box so the drain thread's result survives the closure boundary.
private final class OutputBox: @unchecked Sendable {
    var data: Data?
}

/// Production `PortProbing`: a TCP connect probe to 127.0.0.1 via
/// `NWConnection`, resolved within ~1 second.
public struct LocalhostPortProber: PortProbing {
    public init() {}

    public func isOpen(_ port: UInt16) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: nwPort,
            using: .tcp
        )

        let gate = OneShotGate()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.resume(continuation, returning: true)
                    connection.cancel()
                case .failed, .cancelled:
                    gate.resume(continuation, returning: false)
                case .waiting:
                    // Localhost refusals surface as `.waiting` — treat as
                    // closed instead of spinning until the timeout.
                    gate.resume(continuation, returning: false)
                    connection.cancel()
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                gate.resume(continuation, returning: false)
                connection.cancel()
            }
        }
    }
}

/// Resumes a checked continuation exactly once, even though the connection
/// state handler and the timeout can both fire.
private final class OneShotGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ continuation: CheckedContinuation<Bool, Never>, returning value: Bool) {
        lock.lock()
        let first = !resumed
        resumed = true
        lock.unlock()
        if first { continuation.resume(returning: value) }
    }
}
