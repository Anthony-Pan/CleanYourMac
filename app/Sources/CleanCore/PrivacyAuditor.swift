import Foundation

/// Report-only privacy audit: TCC permission grants, network exposure,
/// security-posture settings, credential file hygiene, and a shell-history
/// secrets heuristic.
///
/// Safety and scope:
///
///  * Findings carry NO file URL (`PrivacyFinding` has no URL field), so audit
///    results are structurally unable to reach the `Cleaner` — the audit can
///    observe, never delete.
///  * Every external effect goes through the injectable `CommandRunning` /
///    `PortProbing` seams. The real implementations use absolute launch paths
///    and hard timeouts (5 s per command, ~1 s per port probe).
///  * Every check is isolated: any failure (missing tool, no Full Disk Access,
///    absent `defaults` key) skips that one check — it never crashes and never
///    blocks the others. An absent defaults key is treated as "off".
///  * Credential checks read permissions METADATA only — never file contents.
///    The history heuristic reports only a match count — never matched text.
public struct PrivacyAuditor: Sendable {
    /// The home directory holding `.ssh`, `.aws`, `.netrc`, and shell history.
    /// Injectable so tests stay inside a sandbox.
    public let homeURL: URL
    /// The `~/Library` base (defaults to `homeURL/Library`).
    public let libraryURL: URL
    let runner: any CommandRunning
    let prober: any PortProbing
    /// The per-user TCC database — queried only when the file exists (absent
    /// on macOS 26+).
    let userTCCPath: String
    /// The system TCC database — readable only with Full Disk Access.
    let systemTCCPath: String

    public init(
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        libraryURL: URL? = nil,
        runner: any CommandRunning = ProcessCommandRunner(),
        prober: any PortProbing = LocalhostPortProber(),
        userTCCPath: String? = nil,
        systemTCCPath: String = "/Library/Application Support/com.apple.TCC/TCC.db"
    ) {
        let library = libraryURL ?? homeURL.appendingPathComponent("Library")
        self.homeURL = homeURL
        self.libraryURL = library
        self.runner = runner
        self.prober = prober
        self.userTCCPath = userTCCPath ?? library
            .appendingPathComponent("Application Support/com.apple.TCC/TCC.db").path
        self.systemTCCPath = systemTCCPath
    }

    // MARK: - Audit

    /// Runs every check and returns the findings sorted most-severe first
    /// (ties keep the stable check order below).
    public func audit() async -> [PrivacyFinding] {
        var findings: [PrivacyFinding] = []
        findings += permissionFindings()
        findings += await portFindings()
        findings += firewallFindings()
        findings += fileVaultFindings()
        findings += analyticsFindings()
        findings += guestFindings()
        findings += airDropFindings()
        findings += credentialFindings()
        findings += historyFindings()

        return findings.enumerated()
            .sorted { a, b in
                a.element.severity == b.element.severity
                    ? a.offset < b.offset
                    : a.element.severity > b.element.severity
            }
            .map(\.element)
    }

    // MARK: - 1. TCC permissions

    // The TCC check (interesting-service table, `permissionFindings()`, and the
    // row→finding mapping) lives in TCCPermissionReader.swift alongside the
    // SQLite reader it depends on.

    /// Privacy & Security deep link for a given anchor (`Privacy_Camera` etc.).
    static func settingsLink(anchor: String) -> String {
        "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
    }

    // MARK: - 2. Network exposure (port probes)

    private static let sharingSettingsLink =
        "x-apple.systempreferences:com.apple.Sharing-Settings.extension"

    private func portFindings() async -> [PrivacyFinding] {
        var out: [PrivacyFinding] = []
        if await prober.isOpen(22) {
            out.append(PrivacyFinding(
                id: "port-22", severity: .warning, category: .networkExposure,
                title: "Remote Login (SSH) is enabled",
                detail: "An SSH server is listening on this Mac. If it's reachable on your network, others can attempt to log in.",
                recommendation: "Turn off Remote Login in Sharing settings unless you use it.",
                settingsURLString: Self.sharingSettingsLink
            ))
        }
        if await prober.isOpen(5900) {
            out.append(PrivacyFinding(
                id: "port-5900", severity: .warning, category: .networkExposure,
                title: "Screen Sharing is enabled",
                detail: "A screen-sharing server is listening on this Mac. If it's reachable on your network, your screen can be viewed remotely.",
                recommendation: "Turn off Screen Sharing in Sharing settings unless you use it.",
                settingsURLString: Self.sharingSettingsLink
            ))
        }
        if await prober.isOpen(445) {
            out.append(PrivacyFinding(
                id: "port-445", severity: .advisory, category: .networkExposure,
                title: "File Sharing (SMB) is enabled",
                detail: "An SMB file-sharing server is listening on this Mac. If it's reachable on your network, shared folders may be visible.",
                recommendation: "Turn off File Sharing in Sharing settings unless you use it.",
                settingsURLString: Self.sharingSettingsLink
            ))
        }
        return out
    }

    // MARK: - 3. Firewall

    /// Parses `socketfilterfw --getglobalstate` output. `true` when disabled,
    /// `false` when enabled (state 1 or 2), `nil` when unrecognisable.
    static func firewallDisabled(from output: String) -> Bool? {
        if output.contains("State = 0") { return true }
        if output.contains("State = 1") || output.contains("State = 2") { return false }
        return nil
    }

    private func firewallFindings() -> [PrivacyFinding] {
        guard let output = runner.run(
            "/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"]
        ), Self.firewallDisabled(from: output) == true else { return [] }
        return [PrivacyFinding(
            id: "firewall-off", severity: .warning, category: .networkExposure,
            title: "Firewall is turned off",
            detail: "The macOS application firewall is disabled, so any app can accept incoming network connections.",
            recommendation: "Turn on the firewall in Network settings.",
            settingsURLString: "x-apple.systempreferences:com.apple.Firewall-Settings.extension"
        )]
    }

    // MARK: - 4. FileVault

    /// Parses `fdesetup status` output. `true` when FileVault is off, `false`
    /// when on, `nil` when unrecognisable.
    static func fileVaultOff(from output: String) -> Bool? {
        if output.contains("FileVault is Off") { return true }
        if output.contains("FileVault is On") { return false }
        return nil
    }

    private func fileVaultFindings() -> [PrivacyFinding] {
        guard let output = runner.run("/usr/bin/fdesetup", ["status"]),
              Self.fileVaultOff(from: output) == true else { return [] }
        return [PrivacyFinding(
            id: "filevault-off", severity: .warning, category: .systemSettings,
            title: "FileVault is turned off",
            detail: "Your startup disk is not encrypted — anyone with physical access to this Mac can read your files.",
            recommendation: "Turn on FileVault in Privacy & Security settings.",
            settingsURLString: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?FileVault"
        )]
    }

    // MARK: - 5–7. defaults-backed settings

    /// True when a `defaults read` output is the boolean "1". A `nil` output
    /// (absent key, unreadable domain) means the setting is off.
    static func defaultsFlagIsOn(_ output: String?) -> Bool {
        output?.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    private func analyticsFindings() -> [PrivacyFinding] {
        let output = runner.run("/usr/bin/defaults", [
            "read",
            "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist",
            "AutoSubmit",
        ])
        guard Self.defaultsFlagIsOn(output) else { return [] }
        return [PrivacyFinding(
            id: "analytics-on", severity: .info, category: .systemSettings,
            title: "Mac analytics sharing is on",
            detail: "Diagnostic and usage data is shared with Apple automatically.",
            recommendation: "Review this under Privacy & Security → Analytics & Improvements.",
            settingsURLString: Self.settingsLink(anchor: "Privacy_Analytics")
        )]
    }

    private func guestFindings() -> [PrivacyFinding] {
        let output = runner.run("/usr/bin/defaults", [
            "read", "/Library/Preferences/com.apple.loginwindow", "GuestEnabled",
        ])
        guard Self.defaultsFlagIsOn(output) else { return [] }
        return [PrivacyFinding(
            id: "guest-on", severity: .advisory, category: .systemSettings,
            title: "Guest user is enabled",
            detail: "Anyone can log in to this Mac as Guest without a password.",
            recommendation: "Turn off the Guest user in Users & Groups settings.",
            settingsURLString: "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension"
        )]
    }

    private func airDropFindings() -> [PrivacyFinding] {
        let output = runner.run("/usr/bin/defaults", [
            "read", "com.apple.sharingd", "DiscoverableMode",
        ])
        let mode = output?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == "Everyone" else { return [] }
        return [PrivacyFinding(
            id: "airdrop-everyone", severity: .advisory, category: .networkExposure,
            title: "AirDrop is discoverable by everyone",
            detail: "Any nearby device can see this Mac and send it AirDrop requests.",
            recommendation: "Set AirDrop to Contacts Only or off in General → AirDrop & Handoff.",
            settingsURLString: "x-apple.systempreferences:com.apple.AirDrop-Hover-Settings.extension"
        )]
    }

    // MARK: - 8. Credential hygiene (permissions metadata only)

    /// True when the POSIX mode grants any group/other access (read, write, or
    /// execute) — i.e. `mode & 0o077 != 0`.
    static func isGroupOrWorldAccessible(_ posixPermissions: Int) -> Bool {
        posixPermissions & 0o077 != 0
    }

    /// True for `~/.ssh` entries that plausibly hold a private key: everything
    /// except public keys, the client config, and the host/authorization lists.
    static func isPrivateSSHKeyCandidate(_ name: String) -> Bool {
        !name.hasSuffix(".pub")
            && name != "config"
            && !name.hasPrefix("known_hosts")
            && !name.hasPrefix("authorized_keys")
    }

    private func credentialFindings() -> [PrivacyFinding] {
        var out: [PrivacyFinding] = []

        // Loose private keys in ~/.ssh. NEVER read file contents — the check
        // is purely the POSIX permission bits.
        let sshDir = homeURL.appendingPathComponent(".ssh")
        let entries = ((try? FileManager.default.contentsOfDirectory(
            at: sshDir, includingPropertiesForKeys: nil
        )) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }

        var looseKeys: [String] = []
        for entry in entries where Self.isPrivateSSHKeyCandidate(entry.lastPathComponent) {
            if looselyPermittedRegularFile(entry) {
                looseKeys.append(entry.lastPathComponent)
            }
        }
        if !looseKeys.isEmpty {
            let noun = looseKeys.count == 1 ? "key is" : "keys are"
            out.append(PrivacyFinding(
                id: "ssh-key-permissions", severity: .warning, category: .credentialHygiene,
                title: "SSH private \(noun) readable by others",
                detail: "In ~/.ssh, permissions allow other users to read: \(looseKeys.joined(separator: ", ")).",
                recommendation: "Run `chmod 600` on each private key in ~/.ssh."
            ))
        }

        // Other well-known credential files.
        if looselyPermittedRegularFile(homeURL.appendingPathComponent(".aws/credentials")) {
            out.append(PrivacyFinding(
                id: "aws-credentials-permissions", severity: .warning, category: .credentialHygiene,
                title: "AWS credentials are readable by others",
                detail: "~/.aws/credentials has permissions that allow other users to read it.",
                recommendation: "Run `chmod 600 ~/.aws/credentials`."
            ))
        }
        if looselyPermittedRegularFile(homeURL.appendingPathComponent(".netrc")) {
            out.append(PrivacyFinding(
                id: "netrc-permissions", severity: .warning, category: .credentialHygiene,
                title: "~/.netrc is readable by others",
                detail: "~/.netrc stores login credentials and has permissions that allow other users to read it.",
                recommendation: "Run `chmod 600 ~/.netrc`."
            ))
        }

        return out
    }

    /// True when `url` is a regular file whose permission bits grant any
    /// group/other access. Reads attributes only — never contents.
    private func looselyPermittedRegularFile(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let permissions = attributes[.posixPermissions] as? Int else { return false }
        return Self.isGroupOrWorldAccessible(permissions)
    }

    // MARK: - 9. Shell-history secrets heuristic

    /// Matches credential-shaped assignments like `PASSWORD=…`, `token: …`,
    /// `api_key=…`. Case-insensitive; requires an `=`/`:` plus a value, so
    /// plain words ("keyboard", "secretariat") never match.
    private static let secretPattern = try? NSRegularExpression(
        pattern: #"(?i)(password|passwd|token|secret|api[_-]?key)\s*[=:]\s*\S"#
    )

    /// The number of credential-shaped matches in `text`. Only ever used for a
    /// count — matched text is never surfaced.
    static func secretLikeMatchCount(in text: String) -> Int {
        guard let regex = secretPattern else { return 0 }
        return regex.numberOfMatches(
            in: text, range: NSRange(text.startIndex..., in: text)
        )
    }

    /// The last `maxBytes` of the file, decoded as lossy UTF-8, or `nil` when
    /// unreadable.
    static func tailText(of url: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func historyFindings() -> [PrivacyFinding] {
        var matches = 0
        for name in [".zsh_history", ".bash_history"] {
            guard let text = Self.tailText(
                of: homeURL.appendingPathComponent(name), maxBytes: 256 * 1024
            ) else { continue }
            matches += Self.secretLikeMatchCount(in: text)
        }
        guard matches > 0 else { return [] }

        let noun = matches == 1 ? "entry" : "entries"
        return [PrivacyFinding(
            id: "history-secrets", severity: .advisory, category: .historyHygiene,
            title: "Your shell history may contain secrets",
            detail: "\(matches) \(noun) in your shell history look like passwords, tokens, or API keys. The matched text is never shown or stored.",
            recommendation: "Review your history and clear it via the opt-in Terminal History trace."
        )]
    }
}
