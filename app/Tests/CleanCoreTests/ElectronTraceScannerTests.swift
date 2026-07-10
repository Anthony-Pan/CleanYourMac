import XCTest
@testable import CleanCore

/// Tests for the Chromium-embedded ("Electron") app trace scanner: strict
/// signature detection, the fixed trace table (nothing else is ever offered),
/// tier/partition handling, and removal safety through the shared gate — all
/// inside a temp `~/Library` sandbox so they never touch real app data.
final class ElectronTraceScannerTests: XCTestCase {
    var sandbox: URL!
    var library: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cym-electron-\(UUID().uuidString)")
        library = sandbox.appendingPathComponent("Library")
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: sandbox)
    }

    // MARK: - Fixtures

    private func traceScanner() -> ElectronTraceScanner {
        ElectronTraceScanner(libraryURL: library)
    }

    private func engine(_ disposer: FileDisposer = RecordingDisposer()) -> PrivacyScanner {
        PrivacyScanner(libraryURL: library, disposer: disposer)
    }

    @discardableResult
    private func makeFile(_ relative: String, bytes: Int = 1_024) throws -> URL {
        let url = library.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: url.path, contents: Data(repeating: 0x41, count: bytes)))
        return url
    }

    @discardableResult
    private func makeDir(_ relative: String, bytes: Int = 2_048) throws -> URL {
        let url = library.appendingPathComponent(relative)
        try fm.createDirectory(at: url.appendingPathComponent("payload"), withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: url.appendingPathComponent("payload/f").path,
                                    contents: Data(repeating: 0x42, count: bytes)))
        return url
    }

    /// A realistic Slack-style Electron layout: engine caches and profile
    /// stores at the top level, plus content/config decoys that must never be
    /// offered.
    private func installSlack() throws {
        let slack = "Application Support/Slack"
        try makeDir("\(slack)/Code Cache")          // engine marker
        try makeDir("\(slack)/Cache")               // disposable cache
        try makeDir("\(slack)/Local Storage")       // profile store (site data)
        try makeFile("\(slack)/Cookies")            // cookies database
        try makeFile("\(slack)/Cookies-wal")        // SQLite sidecar
    }

    // MARK: - Detection

    func test_detectsElectronAppBySignature() throws {
        try installSlack()
        let groups = traceScanner().groups()
        let slack = try XCTUnwrap(groups.first {
            $0.app == .electron(name: "Slack", bundleID: "com.tinyspeck.slackmacgap")
        }, "Slack must be detected with its known bundle id")

        let kinds = Set(slack.items.map(\.kind))
        XCTAssertEqual(kinds, [.caches, .cookies, .siteData])

        let names = Set(slack.items.map { $0.url.lastPathComponent })
        XCTAssertTrue(names.isSuperset(of: ["Cache", "Code Cache", "Local Storage",
                                            "Cookies", "Cookies-wal"]))
    }

    func test_cacheOnlyNativeDirNotDetected() throws {
        // BambuStudio-style native app: a lone Cache directory is NOT a
        // Chromium signature and must never be detected.
        try makeDir("Application Support/BambuStudio/Cache")
        XCTAssertTrue(traceScanner().groups().isEmpty,
                      "a lone Cache directory must not match the electron signature")
    }

    func test_contentAndConfigSiblingsNeverOffered() throws {
        // Cursor-style app: User/ settings, config JSON, and databases sit right
        // beside the traces and must be structurally out of reach.
        let cursor = "Application Support/Cursor"
        try makeDir("\(cursor)/Code Cache")
        try makeDir("\(cursor)/Local Storage")
        try makeDir("\(cursor)/User")                          // user settings
        try makeFile("\(cursor)/claude_desktop_config.json")   // config
        try makeFile("\(cursor)/macros.db")                    // app database
        try makeFile("\(cursor)/projects-v1.json")             // app content

        let group = try XCTUnwrap(traceScanner().groups().first)
        let names = Set(group.items.map { $0.url.lastPathComponent })
        for forbidden in ["User", "claude_desktop_config.json", "macros.db", "projects-v1.json"] {
            XCTAssertFalse(names.contains(forbidden),
                           "\(forbidden) is app content/config and must never be offered")
        }
    }

    func test_loginDataInsideElectronDirNeverOfferedAndBlockedInClear() throws {
        try installSlack()
        let loginData = try makeFile("Application Support/Slack/Login Data")

        let group = try XCTUnwrap(traceScanner().groups().first)
        XCTAssertFalse(group.items.contains { $0.url.lastPathComponent == "Login Data" },
                       "Login Data must never be offered, even inside an electron dir")

        // Even a hand-crafted item must be refused with .protectedContent.
        let bogus = PrivacyItem(
            app: .electron(name: "Slack", bundleID: nil),
            kind: .cookies, url: loginData, sizeBytes: 1_024
        )
        let disposer = RecordingDisposer()
        let report = engine(disposer).clear([bogus], dryRun: false)

        XCTAssertTrue(report.blocked.contains { $0.reason == .protectedContent })
        XCTAssertTrue(fm.fileExists(atPath: loginData.path), "Login Data must survive")
        XCTAssertTrue(disposer.disposed.isEmpty)
    }

    // MARK: - Tiers

    func test_partitionsTierDetectedWithContextBadge() throws {
        // Claude-style app: traces live under Partitions/<name>/, nothing at top.
        let partition = "Application Support/Claude/Partitions/abc123"
        try makeDir("\(partition)/Code Cache")
        try makeDir("\(partition)/Local Storage")

        let group = try XCTUnwrap(traceScanner().groups().first {
            $0.app == .electron(name: "Claude", bundleID: "com.anthropic.claudefordesktop")
        })
        XCTAssertFalse(group.items.isEmpty)
        for item in group.items {
            XCTAssertEqual(item.context, "abc123",
                           "Partitions-tier items must carry the partition name as context")
        }
    }

    func test_defaultTierDetectedWithoutOfferingHistory() throws {
        // A full-Chromium embedder with a Default/ profile. History and Sessions
        // may hold app data for an unknown embedder — deliberately NOT offered.
        let app = "Application Support/SomeChromiumApp"
        try makeFile("\(app)/Local State")            // profile store at top level
        try makeDir("\(app)/Default/GPUCache")        // engine marker in tier
        try makeDir("\(app)/Default/IndexedDB")       // site data in tier
        try makeFile("\(app)/Default/History")        // NOT a generic trace
        try makeDir("\(app)/Default/Sessions")        // NOT a generic trace

        let group = try XCTUnwrap(traceScanner().groups().first)
        let names = Set(group.items.map { $0.url.lastPathComponent })
        XCTAssertTrue(names.contains("GPUCache"))
        XCTAssertTrue(names.contains("IndexedDB"))
        XCTAssertFalse(names.contains("History"),
                       "History must never be offered for an unknown embedder")
        XCTAssertFalse(names.contains("Sessions"),
                       "Sessions must never be offered for an unknown embedder")
        for item in group.items {
            XCTAssertNil(item.context, "Default-tier items must carry nil context")
        }
    }

    // MARK: - Skips

    func test_knownBrowserVendorDirsSkipped() throws {
        // A full signature inside a known browser vendor dir must be ignored —
        // the browser scanner owns those locations.
        for vendor in ["Google", "Vivaldi", "com.operasoftware.Opera"] {
            try makeDir("Application Support/\(vendor)/Code Cache")
            try makeDir("Application Support/\(vendor)/Local Storage")
        }
        XCTAssertTrue(traceScanner().groups().isEmpty,
                      "known browser vendor dirs must never yield electron groups")
    }

    func test_comAppleDirsSkipped() throws {
        try makeDir("Application Support/com.apple.WebFoo/Code Cache")
        try makeDir("Application Support/com.apple.WebFoo/Local Storage")
        XCTAssertTrue(traceScanner().groups().isEmpty,
                      "com.apple.* dirs must never yield electron groups")
    }

    // MARK: - Removal safety

    func test_electronItemsValidateAgainstAllowedRoots() throws {
        try installSlack()
        let scanner = engine()
        let items = scanner.scan().flatMap(\.items)
        XCTAssertFalse(items.isEmpty)

        let policy = SafetyPolicy(allowedRoots: scanner.allowedRoots(),
                                  allowedExactTargets: scanner.exactTargets())
        for item in items {
            XCTAssertNil(policy.validate(item.url),
                         "\(item.url.lastPathComponent) must be inside a detected root")
        }
    }

    func test_electronClearThroughGateRemovesTraces() throws {
        try installSlack()
        let disposer = RecordingDisposer()
        let scanner = engine(disposer)
        let items = scanner.scan().flatMap(\.items)

        let report = scanner.clear(items, dryRun: false)
        XCTAssertTrue(report.blocked.isEmpty)
        XCTAssertTrue(report.failed.isEmpty)
        for item in items {
            XCTAssertFalse(fm.fileExists(atPath: item.url.path))
        }
    }

    func test_craftedElectronItemWithNonTraceBasenameBlocked() throws {
        // The structural check: an electron-attributed item whose basename is
        // not in the fixed trace set must be blocked .protectedContent even
        // though it sits INSIDE a detected root.
        try installSlack()
        let content = try makeFile("Application Support/Slack/projects-v1.json")

        let bogus = PrivacyItem(
            app: .electron(name: "Slack", bundleID: nil),
            kind: .caches, url: content, sizeBytes: 1_024
        )
        let disposer = RecordingDisposer()
        let report = engine(disposer).clear([bogus], dryRun: false)

        XCTAssertTrue(report.blocked.contains { $0.reason == .protectedContent },
                      "a non-trace basename must be blocked .protectedContent")
        XCTAssertTrue(fm.fileExists(atPath: content.path), "app content must survive")
        XCTAssertTrue(disposer.disposed.isEmpty)
    }

    func test_craftedElectronItemOutsideDetectedRootsBlocked() throws {
        // A trace-named file OUTSIDE every detected root must be refused by the
        // safety gate with .outsideAllowedRoots.
        try installSlack()
        let outside = sandbox.appendingPathComponent("Elsewhere/Cache")
        try fm.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: outside.path, contents: Data("keep".utf8)))

        let bogus = PrivacyItem(
            app: .electron(name: "Slack", bundleID: nil),
            kind: .caches, url: outside, sizeBytes: 4
        )
        let disposer = RecordingDisposer()
        let report = engine(disposer).clear([bogus], dryRun: false)

        XCTAssertTrue(report.blocked.contains { $0.reason == .outsideAllowedRoots })
        XCTAssertTrue(fm.fileExists(atPath: outside.path), "the outside file must survive")
        XCTAssertTrue(disposer.disposed.isEmpty)
    }

    func test_mislabeledItemInsideElectronRootStillBlocked() throws {
        // The structural check is keyed on LOCATION, not the item's self-declared
        // app: a non-trace file inside a detected electron root must be blocked
        // even when the crafted item lies about its app (here, .chrome).
        try installSlack()
        let content = try makeFile("Application Support/Slack/config/secrets.json")

        let bogus = PrivacyItem(
            app: .chrome,   // deliberately mislabeled to dodge an app-keyed check
            kind: .caches, url: content, sizeBytes: 1_024
        )
        let disposer = RecordingDisposer()
        let report = engine(disposer).clear([bogus], dryRun: false)

        XCTAssertTrue(report.blocked.contains { $0.reason == .protectedContent },
                      "a mislabeled non-trace item inside an electron root must be blocked")
        XCTAssertTrue(fm.fileExists(atPath: content.path), "app content must survive")
        XCTAssertTrue(disposer.disposed.isEmpty)
    }

    func test_symlinkedTierEscapingAppSupportIsNotADetectedRoot() throws {
        // A symlinked `Default` pointing outside Application Support must not
        // register as an allowed root, so nothing under the symlink target can
        // ever be reached by the cleaner.
        let slack = "Application Support/Slack"
        try makeDir("\(slack)/Code Cache")          // engine marker at top level
        try makeFile("\(slack)/Cookies")            // profile store at top level

        // A secret directory outside App Support, exposed via a Default symlink.
        let secret = sandbox.appendingPathComponent("Secret")
        try fm.createDirectory(at: secret.appendingPathComponent("Cache"), withIntermediateDirectories: true)
        // Give the symlink target its own engine+store so it *would* match if followed.
        try fm.createDirectory(at: secret.appendingPathComponent("GPUCache"), withIntermediateDirectories: true)
        try fm.createDirectory(at: secret.appendingPathComponent("Local Storage"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            at: library.appendingPathComponent("\(slack)/Default"),
            withDestinationURL: secret
        )

        let roots = traceScanner().detectedRoots().map { $0.canonicalized.path }
        let secretPath = secret.canonicalized.path
        XCTAssertFalse(roots.contains { $0 == secretPath || $0.hasPrefix(secretPath + "/") },
                       "a symlinked tier escaping Application Support must never be an allowed root")
    }
}
