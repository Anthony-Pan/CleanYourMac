import XCTest
@testable import CleanCore

/// Tests for the system-wide macOS trace scanner: QuickLook thumbnails, saved
/// window state, quarantine records, shell history, diagnostic reports — plus
/// exact-target removal safety and the sfl4 Recent Items regression. All inside
/// a temp sandbox (library, home, and Darwin cache dirs are injected) so they
/// never touch real machine paths.
final class SystemTraceScannerTests: XCTestCase {
    var sandbox: URL!
    var library: URL!
    var darwinCache: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cym-system-\(UUID().uuidString)")
        library = sandbox.appendingPathComponent("Library")
        darwinCache = sandbox.appendingPathComponent("DarwinCache")
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
        try fm.createDirectory(at: darwinCache, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: sandbox)
    }

    // MARK: - Fixtures

    /// The scanner under test. `homeURL` defaults to the sandbox (the parent of
    /// `library`); the Darwin cache dir is only wired in when a test asks.
    private func engine(
        _ disposer: FileDisposer = RecordingDisposer(),
        withDarwinCache: Bool = false
    ) -> PrivacyScanner {
        PrivacyScanner(
            libraryURL: library,
            darwinCacheURL: withDarwinCache ? darwinCache : nil,
            disposer: disposer
        )
    }

    @discardableResult
    private func makeFile(_ url: URL, bytes: Int = 1_024) throws -> URL {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: url.path, contents: Data(repeating: 0x41, count: bytes)))
        return url
    }

    @discardableResult
    private func makeDir(_ url: URL, bytes: Int = 2_048) throws -> URL {
        try fm.createDirectory(at: url.appendingPathComponent("payload"), withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: url.appendingPathComponent("payload/f").path,
                                    contents: Data(repeating: 0x42, count: bytes)))
        return url
    }

    private func inLibrary(_ relative: String) -> URL {
        library.appendingPathComponent(relative)
    }

    private func inHome(_ relative: String) -> URL {
        sandbox.appendingPathComponent(relative)
    }

    // MARK: - QuickLook thumbnails

    func test_quickLookCacheFoundViaInjectedDarwinCacheDir() throws {
        try makeDir(darwinCache.appendingPathComponent(
            "com.apple.quicklook.ThumbnailsAgent/com.apple.QuickLook.thumbnailcache"))

        let groups = engine(withDarwinCache: true).scan()
        let quickLook = try XCTUnwrap(groups.first { $0.app == .quickLook })
        XCTAssertEqual(quickLook.items.count, 1, "the cache dir is one whole-directory item")
        XCTAssertEqual(quickLook.items.first?.kind, .thumbnails)
        XCTAssertEqual(quickLook.items.first?.defaultOn, true)
    }

    func test_quickLookHermeticWithoutDarwinCacheURL() throws {
        // The default (nil darwinCacheURL) must never reach the fixture — only
        // production() wires in the real Darwin cache directory.
        try makeDir(darwinCache.appendingPathComponent(
            "com.apple.quicklook.ThumbnailsAgent/com.apple.QuickLook.thumbnailcache"))

        let groups = engine().scan()
        XCTAssertNil(groups.first { $0.app == .quickLook },
                     "without an injected Darwin cache dir there is nothing to find")
    }

    func test_quickLookContainerCandidateFound() throws {
        // The older container path derives from libraryURL and needs no Darwin dir.
        try makeDir(inLibrary(
            "Containers/com.apple.quicklook.ThumbnailsAgent/Data/Library/Caches/com.apple.QuickLook.thumbnailcache"))

        let quickLook = try XCTUnwrap(engine().scan().first { $0.app == .quickLook })
        XCTAssertEqual(quickLook.items.count, 1)
        XCTAssertEqual(quickLook.items.first?.kind, .thumbnails)
    }

    // MARK: - Saved window state

    func test_savedStateOnlySavedStateBundles() throws {
        try makeDir(inLibrary("Saved Application State/com.example.app.savedState"))
        try makeDir(inLibrary("Saved Application State/NotAStateBundle"))
        try makeFile(inLibrary("Saved Application State/stray.plist"))

        let savedState = try XCTUnwrap(engine().scan().first { $0.app == .savedState })
        XCTAssertEqual(savedState.items.count, 1, "only *.savedState bundles are offered")
        XCTAssertEqual(savedState.items.first?.url.lastPathComponent, "com.example.app.savedState")
        XCTAssertEqual(savedState.items.first?.kind, .windowState)
        XCTAssertEqual(savedState.items.first?.defaultOn, false,
                       "window state is disruptive → opt-in")
    }

    // MARK: - Quarantine (download records)

    func test_quarantineSidecarsTravelTogether() throws {
        let db = "Preferences/com.apple.LaunchServices.QuarantineEventsV2"
        try makeFile(inLibrary(db))
        try makeFile(inLibrary("\(db)-wal"))
        try makeFile(inLibrary("\(db)-shm"))

        let quarantine = try XCTUnwrap(engine().scan().first { $0.app == .quarantine })
        let names = Set(quarantine.items.map { $0.url.lastPathComponent })
        XCTAssertEqual(names, ["com.apple.LaunchServices.QuarantineEventsV2",
                               "com.apple.LaunchServices.QuarantineEventsV2-wal",
                               "com.apple.LaunchServices.QuarantineEventsV2-shm"],
                       "SQLite sidecars must be cleared together with the database")
        for item in quarantine.items {
            XCTAssertEqual(item.kind, .downloadRecords)
            XCTAssertEqual(item.defaultOn, true)
        }
    }

    // MARK: - Shell history

    func test_shellHistoryFoundAndOptIn() throws {
        try makeFile(inHome(".zsh_history"))
        try makeFile(inHome(".bash_history"))
        try makeDir(inHome(".zsh_sessions"))

        let shell = try XCTUnwrap(engine().scan().first { $0.app == .shellHistory })
        let names = Set(shell.items.map { $0.url.lastPathComponent })
        XCTAssertEqual(names, [".zsh_history", ".bash_history", ".zsh_sessions"])
        XCTAssertEqual(shell.items.filter { $0.url.lastPathComponent == ".zsh_sessions" }.count, 1,
                       ".zsh_sessions is one whole-directory item")
        for item in shell.items {
            XCTAssertEqual(item.kind, .shellHistory)
            XCTAssertFalse(item.defaultOn, "shell history is irreversible → opt-in")
        }
    }

    // MARK: - Diagnostic reports

    func test_diagnosticsFilesAndRetiredAsOneItem() throws {
        try makeFile(inLibrary("Logs/DiagnosticReports/app-2026.ips"))
        try makeFile(inLibrary("Logs/DiagnosticReports/tool.diag"))
        try makeFile(inLibrary("Logs/DiagnosticReports/Retired/old-1.ips"))
        try makeFile(inLibrary("Logs/DiagnosticReports/Retired/old-2.ips"))

        let diagnostics = try XCTUnwrap(engine().scan().first { $0.app == .diagnostics })
        let names = Set(diagnostics.items.map { $0.url.lastPathComponent })
        XCTAssertEqual(names, ["app-2026.ips", "tool.diag", "Retired"],
                       "top-level report files plus Retired as ONE item")
        for item in diagnostics.items {
            XCTAssertEqual(item.kind, .crashReports)
            XCTAssertEqual(item.defaultOn, true)
        }
    }

    func test_diagnosticsNonReportFilesNotOffered() throws {
        // Only genuine report extensions are offered — a stray file a user
        // parked in the folder must be left alone (it is pre-selected otherwise).
        try makeFile(inLibrary("Logs/DiagnosticReports/crash.ips"))
        try makeFile(inLibrary("Logs/DiagnosticReports/notes.txt"))
        try makeFile(inLibrary("Logs/DiagnosticReports/budget.xlsx"))

        let diagnostics = try XCTUnwrap(engine().scan().first { $0.app == .diagnostics })
        let names = Set(diagnostics.items.map { $0.url.lastPathComponent })
        XCTAssertEqual(names, ["crash.ips"], "only report-extension files are offered")
    }

    // MARK: - Removal safety

    func test_clearThroughGateRemovesSystemTraces() throws {
        try makeFile(inLibrary("Preferences/com.apple.LaunchServices.QuarantineEventsV2"))
        try makeFile(inHome(".zsh_history"))
        try makeDir(inLibrary("Saved Application State/com.example.app.savedState"))
        try makeFile(inLibrary("Logs/DiagnosticReports/app.ips"))

        let disposer = RecordingDisposer()
        let scanner = engine(disposer)
        let items = scanner.scan().flatMap(\.items)
        XCTAssertEqual(items.count, 4)

        let report = scanner.clear(items, dryRun: false)
        XCTAssertTrue(report.blocked.isEmpty)
        XCTAssertTrue(report.failed.isEmpty)
        XCTAssertEqual(report.trashed.count, 4)
        for item in items {
            XCTAssertFalse(fm.fileExists(atPath: item.url.path))
        }
    }

    func test_exactTargetsValidateAgainstThePolicy() throws {
        try makeFile(inLibrary("Preferences/com.apple.LaunchServices.QuarantineEventsV2"))
        try makeFile(inHome(".zsh_history"))
        try makeDir(darwinCache.appendingPathComponent(
            "com.apple.quicklook.ThumbnailsAgent/com.apple.QuickLook.thumbnailcache"))

        let scanner = engine(withDarwinCache: true)
        let items = scanner.scan().flatMap(\.items).filter {
            [.quarantine, .shellHistory, .quickLook].contains($0.app)
        }
        XCTAssertFalse(items.isEmpty)

        let policy = SafetyPolicy(allowedRoots: scanner.allowedRoots(),
                                  allowedExactTargets: scanner.exactTargets())
        for item in items {
            XCTAssertNil(policy.validate(item.url),
                         "\(item.url.lastPathComponent) must be a declared exact target")
        }
    }

    func test_siblingNextToExactTargetRefused() throws {
        // ~/.zshrc sits right beside ~/.zsh_history but holds the user's own
        // configuration — it must never pass while the history file does.
        try makeFile(inHome(".zsh_history"))
        let zshrc = try makeFile(inHome(".zshrc"))

        let disposer = RecordingDisposer()
        let scanner = engine(disposer)
        let bogus = PrivacyItem(app: .shellHistory, kind: .shellHistory, url: zshrc, sizeBytes: 1_024)
        let report = scanner.clear([bogus], dryRun: false)

        XCTAssertTrue(report.blocked.contains { $0.reason == .outsideAllowedRoots },
                      ".zshrc must be refused — it is not a declared exact target")
        XCTAssertTrue(fm.fileExists(atPath: zshrc.path), ".zshrc must survive")
        XCTAssertTrue(disposer.disposed.isEmpty)

        let history = scanner.scan().flatMap(\.items).first { $0.url.lastPathComponent == ".zsh_history" }
        XCTAssertNotNil(history, ".zsh_history itself must still be offered")
    }

    // MARK: - macOS Recent Items (sfl4 regression)

    func test_sfl4PrefixedApplicationRecentDocumentsDetected() throws {
        // macOS 26+ names the per-app recents directory with the shared-file-list
        // domain prefix — the scanner must match both spellings.
        try makeDir(inLibrary(
            "Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments"))

        let recents = try XCTUnwrap(engine().scan().first { $0.app == .systemRecents })
        let appRecents = recents.items.filter { $0.kind == .appRecents }
        XCTAssertEqual(appRecents.count, 1,
                       "the prefixed ApplicationRecentDocuments dir must produce exactly one item")
        XCTAssertEqual(appRecents.first?.url.lastPathComponent,
                       "com.apple.LSSharedFileList.ApplicationRecentDocuments")
    }
}
