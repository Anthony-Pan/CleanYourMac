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
        // Only Chrome installed → no Edge/Brave/Firefox/Safari/Arc/Opera/etc. groups.
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
            case .caches, .history, .downloads,
                 .recentDocuments, .recentApplications, .recentServers, .appRecents:
                XCTAssertTrue(item.defaultOn, "\(item.kind) should be pre-selected")
            case .cookies, .sessions, .siteData:
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

    // MARK: - New browsers: Arc (standard layout) and Opera (flat layout)

    func test_arcDetectedWithStandardChromiumLayout() throws {
        // Arc uses Default/ inside Arc/User Data, just like Chrome.
        let profile = "Application Support/Arc/User Data/Default"
        try makeDir("Caches/Arc")
        try makeFile("\(profile)/History")
        try makeFile("\(profile)/Network/Cookies")
        try makeDir("\(profile)/Sessions")

        let groups = scanner().scan()
        let arc = try XCTUnwrap(groups.first { $0.app == .arc }, "Arc group must be found")
        let kinds = Set(arc.items.map(\.kind))
        XCTAssertTrue(kinds.contains(.caches), "Arc cache must be found")
        XCTAssertTrue(kinds.contains(.history), "Arc history must be found")
        XCTAssertTrue(kinds.contains(.cookies), "Arc cookies must be found")
    }

    func test_arcProfilePathsValidateAgainstAllowedRoots() throws {
        // Items found inside Arc/User Data/Default must pass the safety gate.
        let profile = "Application Support/Arc/User Data/Default"
        try makeFile("Caches/Arc/data")
        try makeFile("\(profile)/History")

        let engine = scanner()
        let arcItems = engine.scan().first { $0.app == .arc }?.items ?? []
        XCTAssertFalse(arcItems.isEmpty, "need at least one Arc item to validate")

        let roots = engine.allowedRoots()
        let policy = SafetyPolicy(allowedRoots: roots)
        for item in arcItems {
            XCTAssertNil(policy.validate(item.url),
                         "\(item.url.lastPathComponent) must be inside an allowed root")
        }
    }

    func test_operaDetectedWithFlatLayout() throws {
        // Opera stores profile files directly in the vendor directory.
        let vendor = "Application Support/com.operasoftware.Opera"
        try makeDir("Caches/com.operasoftware.Opera")
        try makeFile("\(vendor)/History")
        try makeFile("\(vendor)/Cookies")

        let groups = scanner().scan()
        let opera = try XCTUnwrap(groups.first { $0.app == .opera }, "Opera group must be found")
        let kinds = Set(opera.items.map(\.kind))
        XCTAssertTrue(kinds.contains(.caches))
        XCTAssertTrue(kinds.contains(.history))
        XCTAssertTrue(kinds.contains(.cookies))
    }

    func test_operaFlatProfileNotNested() throws {
        // Opera has no Default/ subdir — files are directly in the vendor dir.
        // Verify no items are attributed to a non-existent Default/ subdir.
        let vendor = "Application Support/com.operasoftware.Opera"
        try makeFile("Caches/com.operasoftware.Opera/data")
        try makeFile("\(vendor)/History")

        let opera = try XCTUnwrap(scanner().scan().first { $0.app == .opera })
        for item in opera.items where item.url.path.contains("Default") {
            XCTFail("Opera must not use a Default/ subdir; found: \(item.url.path)")
        }
    }

    // MARK: - Chromium multi-profile

    func test_chromiumMultiProfileContextSet() throws {
        // Profile 1 items should carry context == "Profile 1"; Default items carry nil.
        let vendor = "Application Support/Google/Chrome"
        try makeFile("Caches/Google/Chrome/data")
        try makeFile("\(vendor)/Default/History")
        try makeFile("\(vendor)/Profile 1/History")
        try makeFile("\(vendor)/Profile 1/Network/Cookies")

        let chrome = try XCTUnwrap(scanner().scan().first { $0.app == .chrome })
        let profile1Items = chrome.items.filter { $0.context == "Profile 1" }
        XCTAssertFalse(profile1Items.isEmpty, "Profile 1 items must carry context")

        let defaultItems = chrome.items.filter {
            $0.url.path.contains("/Default/") && $0.context != nil
        }
        XCTAssertTrue(defaultItems.isEmpty, "Default profile items must have nil context")
    }

    func test_chromiumProfile1PathsValidateAgainstAllowedRoots() throws {
        let vendor = "Application Support/Google/Chrome"
        try makeFile("\(vendor)/Default/History")
        try makeFile("\(vendor)/Profile 1/History")

        let engine = scanner()
        let items = engine.scan().first { $0.app == .chrome }?.items ?? []
        let profile1Items = items.filter { $0.context == "Profile 1" }
        XCTAssertFalse(profile1Items.isEmpty)

        let roots = engine.allowedRoots()
        let policy = SafetyPolicy(allowedRoots: roots)
        for item in profile1Items {
            XCTAssertNil(policy.validate(item.url),
                         "Profile 1 item must be inside an allowed root")
        }
    }

    // MARK: - Chrome extra history files and new trace kinds

    func test_chromiumExtraHistoryFilesAttributedCorrectly() throws {
        let profile = "Application Support/Google/Chrome/Default"
        try makeFile("Caches/Google/Chrome/data")
        try makeFile("\(profile)/History")
        try makeFile("\(profile)/Visited Links")
        try makeFile("\(profile)/Favicons")
        try makeFile("\(profile)/Top Sites")

        let chrome = try XCTUnwrap(scanner().scan().first { $0.app == .chrome })
        let historyNames = Set(
            chrome.items.filter { $0.kind == .history }.map { $0.url.lastPathComponent }
        )
        XCTAssertTrue(historyNames.contains("History"), "History must be .history")
        XCTAssertTrue(historyNames.contains("Visited Links"), "Visited Links must be .history")
        XCTAssertTrue(historyNames.contains("Favicons"), "Favicons must be .history")
        XCTAssertTrue(historyNames.contains("Top Sites"), "Top Sites must be .history")
    }

    func test_chromiumPerProfileCachesAttributedToCaches() throws {
        let profile = "Application Support/Google/Chrome/Default"
        try makeFile("Caches/Google/Chrome/data")
        try makeFile("\(profile)/History")
        try makeDir("\(profile)/GPUCache")
        try makeDir("\(profile)/Code Cache")

        let chrome = try XCTUnwrap(scanner().scan().first { $0.app == .chrome })
        let cacheNames = Set(
            chrome.items.filter { $0.kind == .caches }.map { $0.url.lastPathComponent }
        )
        XCTAssertTrue(cacheNames.contains("GPUCache"), "GPUCache must be .caches")
        XCTAssertTrue(cacheNames.contains("Code Cache"), "Code Cache must be .caches")
    }

    func test_chromiumSiteDataKindAndOptIn() throws {
        let profile = "Application Support/Google/Chrome/Default"
        try makeFile("Caches/Google/Chrome/data")
        try makeFile("\(profile)/History")
        try makeDir("\(profile)/Local Storage")
        try makeDir("\(profile)/IndexedDB")

        let chrome = try XCTUnwrap(scanner().scan().first { $0.app == .chrome })
        let siteDataNames = Set(
            chrome.items.filter { $0.kind == .siteData }.map { $0.url.lastPathComponent }
        )
        XCTAssertTrue(siteDataNames.contains("Local Storage"), "Local Storage must be .siteData")
        XCTAssertTrue(siteDataNames.contains("IndexedDB"), "IndexedDB must be .siteData")

        for item in chrome.items.filter({ $0.kind == .siteData }) {
            XCTAssertFalse(item.defaultOn, "siteData must not be pre-selected (opt-in)")
        }
    }

    // MARK: - macOS Recent Items

    func test_systemRecentsGroupFoundWithCorrectKinds() throws {
        let sfl = "Application Support/com.apple.sharedfilelist"
        try makeFile("\(sfl)/com.apple.LSSharedFileList.RecentDocuments.sfl2")
        try makeFile("\(sfl)/com.apple.LSSharedFileList.RecentApplications.sfl2")
        try makeFile("\(sfl)/com.apple.LSSharedFileList.RecentServers.sfl2")
        // ApplicationRecentDocuments is a directory (one item for all per-app recents).
        try makeDir("\(sfl)/ApplicationRecentDocuments")

        let groups = scanner().scan()
        let recents = try XCTUnwrap(groups.first { $0.app == .systemRecents },
                                    "systemRecents group must be found")

        let kinds = Set(recents.items.map(\.kind))
        XCTAssertTrue(kinds.contains(.recentDocuments))
        XCTAssertTrue(kinds.contains(.recentApplications))
        XCTAssertTrue(kinds.contains(.recentServers))
        XCTAssertTrue(kinds.contains(.appRecents))
    }

    func test_applicationRecentDocumentsIsOneItem() throws {
        let sfl = "Application Support/com.apple.sharedfilelist"
        try makeDir("\(sfl)/ApplicationRecentDocuments")

        let recents = try XCTUnwrap(scanner().scan().first { $0.app == .systemRecents })
        let appRecentItems = recents.items.filter { $0.kind == .appRecents }
        XCTAssertEqual(appRecentItems.count, 1,
                       "ApplicationRecentDocuments directory must produce exactly one item")
        XCTAssertEqual(appRecentItems.first?.url.lastPathComponent, "ApplicationRecentDocuments")
    }

    func test_systemRecentsClearedThroughGate() throws {
        let sfl = "Application Support/com.apple.sharedfilelist"
        let fileURL = try makeFile("\(sfl)/com.apple.LSSharedFileList.RecentDocuments.sfl2")

        let disposer = RecordingDisposer()
        let engine = scanner(disposer)
        let items = engine.scan().flatMap(\.items)
        let recentsItems = items.filter { $0.app == .systemRecents }
        XCTAssertFalse(recentsItems.isEmpty)

        let report = engine.clear(recentsItems, dryRun: false)
        XCTAssertTrue(report.failed.isEmpty)
        XCTAssertTrue(report.blocked.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: fileURL.path),
                       "recent items file must be removed after clearing")
    }

    // MARK: - Denylist hardening

    func test_denylistBlocksWalSidecarVariantsAtScanTime() throws {
        // `Login Data-wal` normalises to `login data` (after lowercase + strip -wal)
        // and must never be offered by the scanner.
        let profile = "Application Support/Google/Chrome/Default"
        try makeFile("\(profile)/History")
        try makeFile("\(profile)/Login Data-wal")
        try makeFile("\(profile)/formhistory.sqlite")

        let chrome = try XCTUnwrap(scanner().scan().first { $0.app == .chrome })
        let names = Set(chrome.items.map { $0.url.lastPathComponent })
        XCTAssertFalse(names.contains("Login Data-wal"),
                       "Login Data-wal must never be offered (normalises to a protected name)")
        XCTAssertFalse(names.contains("formhistory.sqlite"),
                       "formhistory.sqlite must never be offered (Firefox autofill)")
    }

    func test_denylistBlocksFormValuesAtScanTime() throws {
        // Safari autofill database "Form Values" (space in name, mixed case) must
        // be blocked after lowercase normalisation.
        let safariDir = "Safari"
        try makeFile("\(safariDir)/History.db")
        try makeFile("\(safariDir)/Form Values")

        let safari = try XCTUnwrap(scanner().scan().first { $0.app == .safari })
        let names = Set(safari.items.map { $0.url.lastPathComponent })
        XCTAssertFalse(names.contains("Form Values"),
                       "Safari Form Values autofill database must never be offered")
    }

    func test_denylistProtectedContentBlockedInClear() throws {
        // Even if a PrivacyItem with a protected basename is hand-crafted and
        // passed directly to clear(), it must be refused with .protectedContent and
        // the file must survive.
        let profile = "Application Support/Google/Chrome/Default"
        try makeFile("\(profile)/History")  // real item so allowedRoots includes Default
        let loginData = try makeFile("\(profile)/Login Data")

        let bogus = PrivacyItem(app: .chrome, kind: .history, url: loginData, sizeBytes: 1_024)
        let disposer = RecordingDisposer()
        let report = scanner(disposer).clear([bogus], dryRun: false)

        XCTAssertTrue(
            report.blocked.contains { $0.reason == .protectedContent },
            "Login Data must be blocked with .protectedContent"
        )
        XCTAssertTrue(
            fm.fileExists(atPath: loginData.path),
            "Login Data file must survive even when targeted directly via clear()"
        )
        XCTAssertFalse(
            disposer.disposed.contains(loginData),
            "Login Data must never be passed to the disposer"
        )
    }

    func test_denylistWalVariantBlockedInClear() throws {
        // A PrivacyItem whose url ends in `-wal` must also be blocked by the
        // defence-in-depth normalisation in clear() (normalises to `login data`).
        let profile = "Application Support/Google/Chrome/Default"
        try makeFile("\(profile)/History")
        let walFile = try makeFile("\(profile)/Login Data-wal")

        let bogus = PrivacyItem(app: .chrome, kind: .history, url: walFile, sizeBytes: 512)
        let disposer = RecordingDisposer()
        let report = scanner(disposer).clear([bogus], dryRun: false)

        XCTAssertTrue(
            report.blocked.contains { $0.reason == .protectedContent },
            "Login Data-wal must be normalised and blocked with .protectedContent"
        )
        XCTAssertTrue(fm.fileExists(atPath: walFile.path), "Login Data-wal must survive")
    }

    func test_operaConfigStoresNeverOfferedNorClearable() throws {
        // Opera's flat layout puts config stores (Preferences, Local State) and
        // Bookmarks directly inside the allowed root, so the denylist is the
        // layer that keeps them safe: never offered by scan, and blocked with
        // .protectedContent even when hand-crafted items target them via clear().
        let opera = "Application Support/com.operasoftware.Opera"
        try makeFile("\(opera)/History")
        let prefs = try makeFile("\(opera)/Preferences")
        let localState = try makeFile("\(opera)/Local State")
        let bookmarks = try makeFile("\(opera)/Bookmarks")

        let group = try XCTUnwrap(scanner().scan().first { $0.app == .opera })
        let names = Set(group.items.map { $0.url.lastPathComponent })
        for forbidden in ["Preferences", "Local State", "Bookmarks"] {
            XCTAssertFalse(names.contains(forbidden), "\(forbidden) must never be offered")
        }

        let disposer = RecordingDisposer()
        let crafted = [prefs, localState, bookmarks].map {
            PrivacyItem(app: .opera, kind: .caches, url: $0, sizeBytes: 1_024)
        }
        let report = scanner(disposer).clear(crafted, dryRun: false)

        XCTAssertEqual(report.blocked.filter { $0.reason == .protectedContent }.count, 3,
                       "all three config/content stores must be blocked")
        XCTAssertTrue(disposer.disposed.isEmpty)
        for url in [prefs, localState, bookmarks] {
            XCTAssertTrue(fm.fileExists(atPath: url.path), "\(url.lastPathComponent) must survive")
        }
    }

    // MARK: - Safari container cookies

    func test_safariContainerCookiesFoundWhenFixtureExists() throws {
        // Create the Safari cookies fixture in the container path.
        let cookiesPath = "Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
        try makeFile(cookiesPath)
        // Also create the Safari dir so the scanner can attempt to list it.
        try fm.createDirectory(
            at: library.appendingPathComponent("Safari"),
            withIntermediateDirectories: true
        )

        let safari = try XCTUnwrap(scanner().scan().first { $0.app == .safari })
        let cookieItems = safari.items.filter { $0.kind == .cookies }
        XCTAssertTrue(
            cookieItems.contains { $0.url.lastPathComponent == "Cookies.binarycookies" },
            "Safari container Cookies.binarycookies must be found when present"
        )
    }

    func test_safariContainerCookiesPathInAllowedRoots() throws {
        // The container Cookies directory must always be in allowedRoots, even
        // without any fixture files.
        let roots = scanner().allowedRoots().map { $0.path }
        XCTAssertTrue(
            roots.contains { $0.hasSuffix("Containers/com.apple.Safari/Data/Library/Cookies") },
            "Safari container cookies directory must be in allowedRoots"
        )
    }
}
