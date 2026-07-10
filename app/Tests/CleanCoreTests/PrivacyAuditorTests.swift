import XCTest
import SQLite3
@testable import CleanCore

/// Tests for the report-only privacy audit: pure parsers, the secrets regex,
/// credential permission logic, TCC row→finding mapping against a fixture
/// SQLite database, and mock-driven full audit runs. Everything lives inside a
/// temp sandbox with injected `CommandRunning`/`PortProbing` seams — no real
/// commands, sockets, or machine paths are ever touched.
final class PrivacyAuditorTests: XCTestCase {
    var sandbox: URL!
    var home: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cym-audit-\(UUID().uuidString)")
        home = sandbox.appendingPathComponent("Home")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: sandbox)
    }

    // MARK: - Fixtures

    private struct StubRunner: CommandRunning {
        /// Canned stdout keyed by "launchPath arg1 arg2 …"; missing ⇒ nil
        /// (launch failure / non-zero exit / absent defaults key).
        var outputs: [String: String] = [:]
        func run(_ launchPath: String, _ arguments: [String]) -> String? {
            outputs[([launchPath] + arguments).joined(separator: " ")]
        }
    }

    private struct StubProber: PortProbing {
        var open: Set<UInt16> = []
        func isOpen(_ port: UInt16) async -> Bool { open.contains(port) }
    }

    /// The auditor under test — every seam points into the sandbox; the TCC
    /// paths default to nonexistent sandbox locations so nothing is readable
    /// unless a test builds a fixture.
    private func auditor(
        runner: CommandRunning = StubRunner(),
        prober: PortProbing = StubProber(),
        userTCCPath: String? = nil,
        systemTCCPath: String? = nil
    ) -> PrivacyAuditor {
        PrivacyAuditor(
            homeURL: home,
            runner: runner,
            prober: prober,
            userTCCPath: userTCCPath ?? sandbox.appendingPathComponent("missing/user-TCC.db").path,
            systemTCCPath: systemTCCPath ?? sandbox.appendingPathComponent("missing/system-TCC.db").path
        )
    }

    @discardableResult
    private func makeFile(
        _ url: URL, contents: String = "payload", permissions: Int? = nil
    ) throws -> URL {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: url.path, contents: Data(contents.utf8)))
        if let permissions {
            try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
        return url
    }

    /// Builds a minimal TCC-shaped SQLite database via the C API.
    private func makeTCCFixture(
        rows: [(service: String, client: String, clientType: Int, auth: Int)]
    ) throws -> String {
        let url = sandbox.appendingPathComponent("fixture-TCC.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, """
        CREATE TABLE access (service TEXT, client TEXT, client_type INTEGER,
                             auth_value INTEGER, extra TEXT)
        """, nil, nil, nil), SQLITE_OK)
        for row in rows {
            XCTAssertEqual(sqlite3_exec(db, """
            INSERT INTO access (service, client, client_type, auth_value)
            VALUES ('\(row.service)', '\(row.client)', \(row.clientType), \(row.auth))
            """, nil, nil, nil), SQLITE_OK)
        }
        return url.path
    }

    // MARK: - Severity ordering

    func test_severityOrdersInfoBelowWarning() {
        XCTAssertLessThan(PrivacyFinding.Severity.info, .advisory)
        XCTAssertLessThan(PrivacyFinding.Severity.advisory, .warning)
    }

    // MARK: - Pure parsers

    func test_firewallParse() {
        XCTAssertEqual(PrivacyAuditor.firewallDisabled(from: "Firewall is disabled. (State = 0)"), true)
        XCTAssertEqual(PrivacyAuditor.firewallDisabled(from: "Firewall is enabled. (State = 1)"), false)
        XCTAssertEqual(PrivacyAuditor.firewallDisabled(from: "Firewall is enabled. (State = 2)"), false)
        XCTAssertNil(PrivacyAuditor.firewallDisabled(from: "no such tool"))
    }

    func test_fileVaultParse() {
        XCTAssertEqual(PrivacyAuditor.fileVaultOff(from: "FileVault is Off."), true)
        XCTAssertEqual(PrivacyAuditor.fileVaultOff(from: "FileVault is On."), false)
        XCTAssertNil(PrivacyAuditor.fileVaultOff(from: "garbage"))
    }

    func test_defaultsFlagTreatsAbsentKeyAsOff() {
        XCTAssertTrue(PrivacyAuditor.defaultsFlagIsOn("1\n"))
        XCTAssertFalse(PrivacyAuditor.defaultsFlagIsOn("0\n"))
        XCTAssertFalse(PrivacyAuditor.defaultsFlagIsOn(nil), "absent key == off")
    }

    // MARK: - Secrets regex

    func test_secretRegexHits() {
        let history = """
        export API_KEY=sk-123456
        mysql -u root --password:hunter2
        PASSWD = swordfish
        curl -H 'token: abc'
        """
        XCTAssertEqual(PrivacyAuditor.secretLikeMatchCount(in: history), 4)
    }

    func test_secretRegexMisses() {
        let history = """
        setxkbmap keyboard=qwerty
        echo secretariat won the race
        brew install monkey=1
        gh auth token
        export EMPTY_PASSWORD=
        """
        XCTAssertEqual(PrivacyAuditor.secretLikeMatchCount(in: history), 0,
                       "plain words and value-less assignments must not match")
    }

    // MARK: - Credential permission logic

    func test_permissionBitsHelper() {
        XCTAssertFalse(PrivacyAuditor.isGroupOrWorldAccessible(0o600))
        XCTAssertFalse(PrivacyAuditor.isGroupOrWorldAccessible(0o700))
        XCTAssertTrue(PrivacyAuditor.isGroupOrWorldAccessible(0o644))
        XCTAssertTrue(PrivacyAuditor.isGroupOrWorldAccessible(0o640))
    }

    func test_sshKeyCandidateFilter() {
        XCTAssertTrue(PrivacyAuditor.isPrivateSSHKeyCandidate("id_rsa"))
        XCTAssertTrue(PrivacyAuditor.isPrivateSSHKeyCandidate("id_ed25519"))
        XCTAssertFalse(PrivacyAuditor.isPrivateSSHKeyCandidate("id_rsa.pub"))
        XCTAssertFalse(PrivacyAuditor.isPrivateSSHKeyCandidate("config"))
        XCTAssertFalse(PrivacyAuditor.isPrivateSSHKeyCandidate("known_hosts"))
        XCTAssertFalse(PrivacyAuditor.isPrivateSSHKeyCandidate("known_hosts.old"))
        XCTAssertFalse(PrivacyAuditor.isPrivateSSHKeyCandidate("authorized_keys"))
    }

    func test_tightSSHKeyProducesNoFinding() async throws {
        try makeFile(home.appendingPathComponent(".ssh/id_test"), permissions: 0o600)

        let findings = await auditor().audit()
        XCTAssertNil(findings.first { $0.id == "ssh-key-permissions" })
    }

    func test_looseSSHKeyProducesWarning() async throws {
        try makeFile(home.appendingPathComponent(".ssh/id_test"), permissions: 0o644)
        try makeFile(home.appendingPathComponent(".ssh/id_test.pub"), permissions: 0o644)
        try makeFile(home.appendingPathComponent(".ssh/config"), permissions: 0o644)

        let findings = await auditor().audit()
        let finding = try XCTUnwrap(findings.first { $0.id == "ssh-key-permissions" })
        XCTAssertEqual(finding.severity, .warning)
        XCTAssertEqual(finding.category, .credentialHygiene)
        XCTAssertTrue(finding.detail.contains("id_test"))
        XCTAssertFalse(finding.detail.contains("id_test.pub"), "public keys are fine to share")
        XCTAssertFalse(finding.detail.contains("config"), "the client config is not a key")
        XCTAssertFalse(finding.detail.contains("payload"),
                       "file CONTENTS must never be read, let alone surfaced")
    }

    func test_awsAndNetrcPermissions() async throws {
        try makeFile(home.appendingPathComponent(".aws/credentials"), permissions: 0o644)
        try makeFile(home.appendingPathComponent(".netrc"), permissions: 0o600)

        let findings = await auditor().audit()
        XCTAssertNotNil(findings.first { $0.id == "aws-credentials-permissions" })
        XCTAssertNil(findings.first { $0.id == "netrc-permissions" },
                     "0600 .netrc is correctly locked down")
    }

    // MARK: - History secrets heuristic

    func test_historySecretsFindingCountsButNeverQuotes() async throws {
        try makeFile(home.appendingPathComponent(".zsh_history"), contents: """
        ls -la
        export API_KEY=sk-livekey-9999
        git push
        mysql --password=hunter2
        """)

        let findings = await auditor().audit()
        let finding = try XCTUnwrap(findings.first { $0.id == "history-secrets" })
        XCTAssertEqual(finding.severity, .advisory)
        XCTAssertEqual(finding.category, .historyHygiene)
        XCTAssertTrue(finding.detail.contains("2"), "two credential-shaped entries")
        XCTAssertFalse(finding.detail.contains("hunter2"), "matched text must never appear")
        XCTAssertFalse(finding.detail.contains("sk-livekey"), "matched text must never appear")
    }

    // MARK: - TCC

    func test_tccFixtureMapsRowsToFindings() async throws {
        let path = try makeTCCFixture(rows: [
            ("kTCCServiceScreenCapture", "com.example.one", 0, 2),
            ("kTCCServiceScreenCapture", "com.example.two", 0, 3),
            ("kTCCServiceScreenCapture", "com.example.two", 0, 3),   // duplicate → deduped
            ("kTCCServiceCamera", "com.example.cam", 0, 2),
            ("kTCCServiceMicrophone", "com.example.mic", 0, 0),      // denied → excluded
            ("kTCCServiceLiveActivity", "com.example.other", 0, 2),  // uninteresting
        ])

        let findings = await auditor(userTCCPath: path).audit()

        let screen = try XCTUnwrap(findings.first { $0.id == "tcc-screen-capture" })
        XCTAssertEqual(screen.severity, .warning)
        XCTAssertEqual(screen.category, .permissions)
        XCTAssertEqual(screen.title, "2 apps can record your screen")
        XCTAssertEqual(screen.apps, ["com.example.one", "com.example.two"])
        XCTAssertEqual(screen.settingsURLString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")

        let camera = try XCTUnwrap(findings.first { $0.id == "tcc-camera" })
        XCTAssertEqual(camera.severity, .advisory)
        XCTAssertEqual(camera.title, "1 app can use your camera")

        XCTAssertNil(findings.first { $0.id == "tcc-microphone" }, "denied rows are excluded")
        XCTAssertNil(findings.first { $0.id == "tcc-unreadable" },
                     "the FDA hint only appears when NEITHER database is readable")
    }

    func test_neitherTCCDatabaseReadableDegradesToOneInfoFinding() async throws {
        let findings = await auditor().audit()
        let tcc = findings.filter { $0.category == .permissions }
        XCTAssertEqual(tcc.map(\.id), ["tcc-unreadable"])
        XCTAssertEqual(tcc.first?.severity, .info)
        XCTAssertEqual(tcc.first?.settingsURLString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    func test_tccReaderRejectsGarbageDatabase() throws {
        let garbage = try makeFile(sandbox.appendingPathComponent("not-a-db.db"),
                                   contents: "definitely not sqlite")
        XCTAssertNil(TCCPermissionReader.grants(atPath: garbage.path))
        XCTAssertNil(TCCPermissionReader.grants(atPath: sandbox.appendingPathComponent("absent.db").path))
    }

    // MARK: - Full mock-driven audit

    private static let allOnOutputs: [String: String] = [
        "/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate":
            "Firewall is disabled. (State = 0)",
        "/usr/bin/fdesetup status": "FileVault is Off.",
        "/usr/bin/defaults read /Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist AutoSubmit": "1\n",
        "/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow GuestEnabled": "1\n",
        "/usr/bin/defaults read com.apple.sharingd DiscoverableMode": "Everyone\n",
    ]

    func test_auditWithAllMocksProducesExpectedStableOrder() async throws {
        let findings = await auditor(
            runner: StubRunner(outputs: Self.allOnOutputs),
            prober: StubProber(open: [22, 5900, 445])
        ).audit()

        // Severity descending, stable check order within each severity band.
        XCTAssertEqual(findings.map(\.id), [
            "port-22", "port-5900", "firewall-off", "filevault-off",   // warnings
            "port-445", "guest-on", "airdrop-everyone",                // advisories
            "tcc-unreadable", "analytics-on",                          // infos
        ])
        XCTAssertEqual(findings.map(\.severity), findings.map(\.severity).sorted(by: >))

        // Structural guarantee spot-check: no finding field is a URL, so
        // nothing here can ever be routed into the Cleaner.
        for finding in findings {
            for child in Mirror(reflecting: finding).children {
                XCTAssertFalse(child.value is URL,
                               "\(finding.id).\(child.label ?? "?") must not be a URL")
            }
        }
    }

    func test_auditIsolatesFailingChecks() async throws {
        // Runner answers nothing, prober sees every port closed, no TCC
        // database, empty home — every check either finds nothing or degrades.
        let findings = await auditor().audit()
        XCTAssertEqual(findings.map(\.id), ["tcc-unreadable"],
                       "failed checks are skipped without crashing or blocking the rest")
    }

    func test_auditFirewallEnabledProducesNoFinding() async throws {
        let findings = await auditor(
            runner: StubRunner(outputs: [
                "/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate":
                    "Firewall is enabled. (State = 1)",
                "/usr/bin/fdesetup status": "FileVault is On.",
                "/usr/bin/defaults read com.apple.sharingd DiscoverableMode": "Contacts Only\n",
            ])
        ).audit()
        XCTAssertNil(findings.first { $0.id == "firewall-off" })
        XCTAssertNil(findings.first { $0.id == "filevault-off" })
        XCTAssertNil(findings.first { $0.id == "airdrop-everyone" })
    }
}
