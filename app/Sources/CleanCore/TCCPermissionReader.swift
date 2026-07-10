import Foundation
import SQLite3

/// Reads granted permission rows out of a TCC database (the macOS privacy
/// permission store) via the SQLite3 C API.
///
/// Safety and scope:
///
///  * The database is opened strictly read-only (`SQLITE_OPEN_READONLY`) —
///    the reader can never modify, create, or checkpoint anything.
///  * Any failure (file missing, no Full Disk Access, schema mismatch, not a
///    SQLite file) returns `nil` so the caller can degrade gracefully.
struct TCCPermissionReader {
    /// One granted row of the TCC `access` table.
    struct Grant: Sendable, Hashable {
        /// TCC service identifier, e.g. `kTCCServiceScreenCapture`.
        let service: String
        /// The grantee — a bundle identifier (`client_type` 0) or an absolute
        /// binary path (`client_type` 1).
        let client: String
    }

    /// All rows whose `auth_value` means granted (2 = allowed, 3 = limited),
    /// or `nil` when the database cannot be opened or queried.
    static func grants(atPath path: String) -> [Grant]? {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db = handle else {
            // Per SQLite docs a handle may be allocated even on failure.
            sqlite3_close(handle)
            return nil
        }
        defer { sqlite3_close(db) }

        // TCC.db is a live database tccd writes to; let a transient write lock
        // retry briefly rather than fail the scan mid-way.
        sqlite3_busy_timeout(db, 250)

        let sql = """
        SELECT service, client, client_type, auth_value \
        FROM access WHERE auth_value IN (2, 3)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let query = statement else {
            return nil
        }
        defer { sqlite3_finalize(query) }

        var grants: [Grant] = []
        var rc = sqlite3_step(query)
        while rc == SQLITE_ROW {
            if let service = sqlite3_column_text(query, 0),
               let client = sqlite3_column_text(query, 1) {
                grants.append(Grant(
                    service: String(cString: service),
                    client: String(cString: client)
                ))
            }
            rc = sqlite3_step(query)
        }
        // Only trust the result if iteration ran to completion. A mid-scan
        // SQLITE_BUSY/IOERR must degrade to nil (caller shows a graceful hint),
        // never a silently truncated grant list presented as authoritative.
        guard rc == SQLITE_DONE else { return nil }
        return grants
    }
}

// MARK: - TCC check (PrivacyAuditor)

/// The TCC permissions check — kept next to the reader it depends on.
extension PrivacyAuditor {
    /// One TCC service worth surfacing, with severity and copy.
    struct TCCService {
        let service: String
        let idSuffix: String
        let severity: PrivacyFinding.Severity
        /// Completes "N apps can …", e.g. "record your screen".
        let capability: String
        /// System Settings → Privacy & Security anchor.
        let anchor: String
    }

    static let interestingTCCServices: [TCCService] = [
        TCCService(service: "kTCCServiceScreenCapture", idSuffix: "screen-capture",
                   severity: .warning, capability: "record your screen",
                   anchor: "Privacy_ScreenCapture"),
        TCCService(service: "kTCCServiceSystemPolicyAllFiles", idSuffix: "full-disk",
                   severity: .warning, capability: "access all your files",
                   anchor: "Privacy_AllFiles"),
        TCCService(service: "kTCCServiceAccessibility", idSuffix: "accessibility",
                   severity: .warning, capability: "control your Mac",
                   anchor: "Privacy_Accessibility"),
        TCCService(service: "kTCCServiceListenEvent", idSuffix: "input-monitoring",
                   severity: .warning, capability: "monitor your keystrokes",
                   anchor: "Privacy_ListenEvent"),
        TCCService(service: "kTCCServiceCamera", idSuffix: "camera",
                   severity: .advisory, capability: "use your camera",
                   anchor: "Privacy_Camera"),
        TCCService(service: "kTCCServiceMicrophone", idSuffix: "microphone",
                   severity: .advisory, capability: "use your microphone",
                   anchor: "Privacy_Microphone"),
        TCCService(service: "kTCCServicePostEvent", idSuffix: "post-event",
                   severity: .advisory, capability: "send keystrokes and clicks",
                   anchor: "Privacy_Accessibility"),
    ]

    func permissionFindings() -> [PrivacyFinding] {
        let fm = FileManager.default
        // User DB only when the file exists (gone on macOS 26+); the system DB
        // open simply fails without Full Disk Access.
        let userGrants: [TCCPermissionReader.Grant]? = fm.fileExists(atPath: userTCCPath)
            ? TCCPermissionReader.grants(atPath: userTCCPath)
            : nil
        let systemGrants = TCCPermissionReader.grants(atPath: systemTCCPath)

        guard userGrants != nil || systemGrants != nil else {
            // Neither database readable — degrade to a single honest hint.
            return [PrivacyFinding(
                id: "tcc-unreadable",
                severity: .info,
                category: .permissions,
                title: "Grant Full Disk Access to audit app permissions",
                detail: "The macOS permission database is protected; without Full Disk Access this app cannot list which apps hold camera, microphone, or screen-recording access.",
                recommendation: "Add this app under Privacy & Security → Full Disk Access, then scan again.",
                settingsURLString: Self.settingsLink(anchor: "Privacy_AllFiles")
            )]
        }

        return Self.findings(for: (userGrants ?? []) + (systemGrants ?? []))
    }

    /// Maps granted TCC rows to at most one finding per interesting service.
    /// Internal so tests can drive it with fixture rows.
    static func findings(for grants: [TCCPermissionReader.Grant]) -> [PrivacyFinding] {
        var out: [PrivacyFinding] = []
        for descriptor in interestingTCCServices {
            let clients = Set(
                grants.filter { $0.service == descriptor.service }.map(\.client)
            ).sorted()
            guard !clients.isEmpty else { continue }

            let noun = clients.count == 1 ? "app" : "apps"
            out.append(PrivacyFinding(
                id: "tcc-\(descriptor.idSuffix)",
                severity: descriptor.severity,
                category: .permissions,
                title: "\(clients.count) \(noun) can \(descriptor.capability)",
                detail: "Granted to: \(clients.joined(separator: ", ")).",
                recommendation: "Review the list in System Settings and revoke anything you don't recognize.",
                settingsURLString: settingsLink(anchor: descriptor.anchor),
                apps: clients
            ))
        }
        return out
    }
}
