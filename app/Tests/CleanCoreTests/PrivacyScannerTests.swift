import XCTest
@testable import CleanCore

/// Tests for the Privacy engine: browser detection, trace attribution, the
/// hard exclusion of passwords/autofill/bookmarks, and removal safety — all
/// inside a temp `~/Library` sandbox so they never touch real browser data or
/// the real Trash.
final class PrivacyScannerTests: XCTestCase {
    var sandbox: URL!
    var library: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cym-privacy-\(UUID().uuidString)")
        library = sandbox.appendingPathComponent("Library")
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: sandbox)
    }

    // MARK: - Fixtures

    private func scanner(_ disposer: FileDisposer = RecordingDisposer()) -> PrivacyScanner {
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

    /// A realistic Chrome profile: privacy traces plus password/autofill/bookmark
    /// decoys that must never be offered.
    private func installChrome() throws {
        let profile = "Application Support/Google/Chrome/Default"
        try makeDir("Caches/Google/Chrome")                       // cache
        try makeFile("\(profile)/History")                        // history
        try makeFile("\(profile)/Network/Cookies")                // cookies (modern location)
        try makeDir("\(profile)/Sessions")                        // open tabs

        // Decoys — the user's own content. MUST NOT be attributed.
        try makeFile("\(profile)/Login Data")                     // saved passwords
        try makeFile("\(profile)/Web Data")                       // autofill / cards
        try makeFile("\(profile)/Bookmarks")                      // bookmarks
        try makeFile("\(profile)/Preferences")
    }

    // MARK: - Detection + attribution

    func test_detectsChromeAndAttributesTraces() throws {
        try installChrome()
        let groups = scanner().scan()
        let chrome = try XCTUnwrap(groups.first { $0.app == .chrome })

        let kinds = Set(chrome.items.map(\.kind))
        XCTAssertEqual(kinds, [.caches, .history, .cookies, .sessions])
    }

    func test_excludesPasswordsAutofillAndBookmarks() throws {
        try installChrome()
        let chrome = try XCTUnwrap(scanner().scan().first { $0.app == .chrome })
        let names = Set(chrome.items.map { $0.url.lastPathComponent })

        for forbidden in ["Login Data", "Web Data", "Bookmarks", "Preferences"] {
            XCTAssertFalse(names.contains(forbidden),
                           "\(forbidden) holds the user's own content and must never be offered")
        }
    }

    func test_firefoxExcludesPlacesSqliteBecauseItHoldsBookmarks() throws {
        let profile = "Application Support/Firefox/Profiles/abc123.default-release"
        try makeDir("Caches/Firefox")
        try makeFile("\(profile)/cookies.sqlite")
        try makeFile("\(profile)/sessionstore.jsonlz4")
        try makeFile("\(profile)/places.sqlite")   // history + BOOKMARKS — must be excluded
        try makeFile("\(profile)/logins.json")      // saved passwords
        try makeFile("\(profile)/key4.db")          // password key store

        let firefox = try XCTUnwrap(scanner().scan().first { $0.app == .firefox })
        let names = Set(firefox.items.map { $0.url.lastPathComponent })

        XCTAssertTrue(names.contains("cookies.sqlite"))
        XCTAssertTrue(names.contains("sessionstore.jsonlz4"))
        for forbidden in ["places.sqlite", "logins.json", "key4.db"] {
            XCTAssertFalse(names.contains(forbidden), "\(forbidden) must never be offered")
        }
    }

    func test_absentBrowserProducesNoGroup() throws {
        // Only Chrome installed → no Edge/Brave/Firefox/Safari groups.
        try installChrome()
        let apps = Set(scanner().scan().map(\.app))
        XCTAssertEqual(apps, [.chrome])
    }

    func test_clearsSqliteSidecarsAlongsideTheDatabase() throws {
        // History.db + its WAL/SHM sidecars must all be found and cleared, or the
        // exact data the user asked to erase survives in the orphaned -wal file.
        let profile = "Application Support/Google/Chrome/Default"
        try makeFile("Caches/Google/Chrome/data")
        try makeFile("\(profile)/History")
        try makeFile("\(profile)/History-wal")
        try makeFile("\(profile)/History-shm")
        try makeFile("\(profile)/Network/Cookies")
        try makeFile("\(profile)/Network/Cookies-wal")

        let chrome = try XCTUnwrap(scanner().scan().first { $0.app == .chrome })
        let names = Set(chrome.items.map { $0.url.lastPathComponent })
        XCTAssertTrue(names.isSuperset(of: ["History", "History-wal", "History-shm", "Cookies", "Cookies-wal"]),
                      "SQLite sidecars must be cleared together with the primary database")
    }

    func test_neverOffersPasswordsEvenIfPathTableWouldReachThem() throws {
        // Defense in depth: even a file literally named like a password store,
        // sitting in an otherwise-cleanable location, must never be offered.
        let profile = "Application Support/Google/Chrome/Default"
        try makeFile("\(profile)/History")
        try makeFile("\(profile)/Login Data")
        try makeFile("\(profile)/Web Data")

        let chrome = try XCTUnwrap(scanner().scan().first { $0.app == .chrome })
        let names = Set(chrome.items.map { $0.url.lastPathComponent })
        XCTAssertTrue(names.contains("History"))
        XCTAssertFalse(names.contains("Login Data"))
        XCTAssertFalse(names.contains("Web Data"))
    }

    func test_allowedRootsNeverIncludeUserContentFolders() throws {
        // The fixed allowlist must never reach the user's documents/desktop/etc.
        let roots = scanner().allowedRoots().map { $0.path }
        for forbidden in ["Documents", "Desktop", "Downloads", "Movies", "Pictures"] {
            XCTAssertFalse(roots.contains { $0.hasSuffix("/\(forbidden)") },
                           "allowedRoots must never include ~/\(forbidden)")
        }
    }

    // MARK: - Default selection semantics

    func test_cookiesAndSessionsAreOptInByDefault() throws {
        try installChrome()
        let chrome = try XCTUnwrap(scanner().scan().first { $0.app == .chrome })
        for item in chrome.items {
            switch item.kind {
            case .caches, .history, .downloads:
                XCTAssertTrue(item.defaultOn, "\(item.kind) should be pre-selected")
            case .cookies, .sessions:
                XCTAssertFalse(item.defaultOn, "\(item.kind) is disruptive → opt-in")
            }
        }
    }

    // MARK: - Removal safety

    func test_dryRunTouchesNothing() throws {
        try installChrome()
        let disposer = RecordingDisposer()
        let engine = scanner(disposer)
        let items = engine.scan().flatMap(\.items)

        let report = engine.clear(items, dryRun: true)
        XCTAssertTrue(disposer.disposed.isEmpty)
        XCTAssertGreaterThan(report.freedBytes, 0)
        for item in items {
            XCTAssertTrue(fm.fileExists(atPath: item.url.path), "a dry run must leave traces in place")
        }
    }

    func test_realClearRemovesSelectedTraces() throws {
        try installChrome()
        let disposer = RecordingDisposer()
        let engine = scanner(disposer)
        let items = engine.scan().flatMap(\.items)

        let report = engine.clear(items, dryRun: false)
        XCTAssertEqual(disposer.disposed.count, items.count)
        XCTAssertEqual(report.trashed.count, items.count)
        XCTAssertTrue(report.failed.isEmpty)
        XCTAssertTrue(report.blocked.isEmpty)
        for item in items {
            XCTAssertFalse(fm.fileExists(atPath: item.url.path))
        }
    }

    /// A crafted item pointing outside any browser location must be refused by
    /// the re-validation gate.
    func test_clearRefusesItemOutsideAllowedRoots() throws {
        let important = sandbox.appendingPathComponent("Documents/important.txt")
        try fm.createDirectory(at: important.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: important.path, contents: Data("keep".utf8)))

        // The policy is derived from the *other* items' parents, so this bogus
        // item lives outside every allowed root.
        let real = try makeFile("Application Support/Google/Chrome/Default/History")
        let good = PrivacyItem(app: .chrome, kind: .history, url: real, sizeBytes: 1_024)
        let bogus = PrivacyItem(app: .chrome, kind: .history, url: important, sizeBytes: 4)

        let disposer = RecordingDisposer()
        let report = scanner(disposer).clear([good, bogus], dryRun: false)

        XCTAssertTrue(report.blocked.contains { $0.reason == .outsideAllowedRoots })
        XCTAssertTrue(fm.fileExists(atPath: important.path), "a file outside browser data must survive")
        XCTAssertFalse(disposer.disposed.contains(important), "the important file must never be disposed")
    }
}
