import XCTest
@testable import CleanCore

/// Tests for the Large & Old Files engine: size/age filtering, type inference,
/// the "skip proxies" rules, and the safety invariants of removal — all inside
/// a temp sandbox so they never touch the real disk or Trash.
final class FileFinderTests: XCTestCase {
    var sandbox: URL!
    var downloads: URL!
    var documents: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cym-large-\(UUID().uuidString)")
        downloads = sandbox.appendingPathComponent("Downloads")
        documents = sandbox.appendingPathComponent("Documents")
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        try fm.createDirectory(at: documents, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: sandbox)
    }

    // MARK: - Fixtures

    private func finder(_ disposer: FileDisposer = RecordingDisposer()) -> FileFinder {
        let roots = [downloads!, documents!]
        return FileFinder(roots: roots, policy: SafetyPolicy(allowedRoots: roots), disposer: disposer)
    }

    @discardableResult
    private func makeFile(_ url: URL, mb: Int, ageDays: Int? = nil) throws -> URL {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: url.path, contents: Data(repeating: 0x41, count: mb * 1_000_000)))
        if let ageDays {
            let date = Date(timeIntervalSinceNow: -Double(ageDays) * 86_400)
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        return url
    }

    // MARK: - Discovery + filters

    func test_findsOnlyFilesAtOrAboveThreshold() throws {
        try makeFile(downloads.appendingPathComponent("big.bin"), mb: 250)
        try makeFile(downloads.appendingPathComponent("small.bin"), mb: 10)

        let files = finder().find(minSizeBytes: 100 * 1_000_000)
        let names = Set(files.map(\.name))
        XCTAssertTrue(names.contains("big.bin"))
        XCTAssertFalse(names.contains("small.bin"), "files below the threshold are excluded")
    }

    func test_recursesIntoSubfoldersAndSortsLargestFirst() throws {
        try makeFile(downloads.appendingPathComponent("a/medium.bin"), mb: 150)
        try makeFile(documents.appendingPathComponent("deep/nested/huge.bin"), mb: 400)

        let files = finder().find(minSizeBytes: 100 * 1_000_000)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files.first?.name, "huge.bin", "results are sorted largest first")
    }

    func test_ageFilterExcludesRecentFiles() throws {
        try makeFile(downloads.appendingPathComponent("old.bin"), mb: 200, ageDays: 400)
        try makeFile(downloads.appendingPathComponent("fresh.bin"), mb: 200, ageDays: 2)

        let old = finder().find(minSizeBytes: 100 * 1_000_000, olderThanDays: 180)
        let names = Set(old.map(\.name))
        XCTAssertTrue(names.contains("old.bin"))
        XCTAssertFalse(names.contains("fresh.bin"), "files newer than the age threshold are excluded")
    }

    func test_inferKindFromExtension() throws {
        try makeFile(downloads.appendingPathComponent("movie.mp4"), mb: 200)
        try makeFile(downloads.appendingPathComponent("archive.zip"), mb: 200)
        try makeFile(downloads.appendingPathComponent("disk.dmg"), mb: 200)

        let byName = Dictionary(uniqueKeysWithValues: finder().find(minSizeBytes: 100 * 1_000_000).map { ($0.name, $0.kind) })
        XCTAssertEqual(byName["movie.mp4"], .video)
        XCTAssertEqual(byName["archive.zip"], .archive)
        XCTAssertEqual(byName["disk.dmg"], .diskImage)
    }

    func test_skipsSymlinks() throws {
        let real = try makeFile(sandbox.appendingPathComponent("outside/secret.bin"), mb: 300)
        let link = downloads.appendingPathComponent("link.bin")
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        let files = finder().find(minSizeBytes: 100 * 1_000_000)
        XCTAssertFalse(files.contains { $0.name == "link.bin" }, "a symlink is never offered as a large file")
    }

    func test_skipsPackageContents() throws {
        // A .app bundle in Downloads: its internals must not surface as files.
        let payload = downloads.appendingPathComponent("Thing.app/Contents/MacOS/big.bin")
        try makeFile(payload, mb: 300)

        let files = finder().find(minSizeBytes: 100 * 1_000_000)
        XCTAssertFalse(files.contains { $0.path.contains(".app/") },
                       "package internals must not be enumerated as loose files")
    }

    // MARK: - Removal safety

    func test_dryRunTouchesNothing() throws {
        let f = try makeFile(downloads.appendingPathComponent("big.bin"), mb: 200)
        let disposer = RecordingDisposer()
        let engine = finder(disposer)
        let files = engine.find(minSizeBytes: 100 * 1_000_000)

        let report = engine.remove(files, dryRun: true)
        XCTAssertTrue(disposer.disposed.isEmpty)
        XCTAssertGreaterThan(report.freedBytes, 0)
        XCTAssertTrue(fm.fileExists(atPath: f.path), "a dry run must leave the file in place")
    }

    func test_realRemoveDisposesSelectedFiles() throws {
        try makeFile(downloads.appendingPathComponent("big.bin"), mb: 200)
        let disposer = RecordingDisposer()
        let engine = finder(disposer)
        let files = engine.find(minSizeBytes: 100 * 1_000_000)

        let report = engine.remove(files, dryRun: false)
        XCTAssertEqual(disposer.disposed.count, files.count)
        XCTAssertEqual(report.trashed.count, files.count)
        XCTAssertTrue(report.failed.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: files[0].path))
    }

    /// THE key safety test: a crafted `LargeFile` pointing outside the scan
    /// roots must be refused by the re-validation gate, even if handed straight
    /// to `remove`.
    func test_removeRefusesFileOutsideRoots() throws {
        let important = sandbox.appendingPathComponent("Elsewhere/important.txt")
        try fm.createDirectory(at: important.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: important.path, contents: Data("keep".utf8)))

        let bogus = LargeFile(url: important, sizeBytes: 4, modificationDate: nil, accessDate: nil, kind: .document)
        let disposer = RecordingDisposer()
        let report = finder(disposer).remove([bogus], dryRun: false)

        XCTAssertTrue(disposer.disposed.isEmpty)
        XCTAssertEqual(report.blocked.first?.reason, .outsideAllowedRoots)
        XCTAssertTrue(fm.fileExists(atPath: important.path), "a file outside the scan roots must survive")
    }

    func test_defaultRootsAreAllInsideHomeContentFolders() {
        let home = fm.homeDirectoryForCurrentUser
        for root in FileFinder.defaultRoots {
            XCTAssertTrue(root.path.hasPrefix(home.path), "default roots live under the home folder: \(root.path)")
            XCTAssertFalse(root.path.contains("/Library"), "default roots never include ~/Library")
        }
    }
}
