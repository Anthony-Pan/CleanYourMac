import XCTest
@testable import CleanCore

/// Space Lens is read-only, so these tests only prove the *measuring* is
/// honest: sizes, ordering, hidden files, symlink containment, package
/// leaf-ness and cancellation. Everything happens in a temp-dir sandbox.
final class SpaceLensScannerTests: XCTestCase {
    var sandbox: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cym-lens-\(UUID().uuidString)")
        try fm.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: sandbox)
    }

    // MARK: - Helpers

    @discardableResult
    private func makeFile(_ relative: String, bytes: Int) throws -> URL {
        let url = sandbox.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: bytes).write(to: url)
        return url
    }

    /// The same size chain the scanner uses (allocated with logical fallback),
    /// measured independently so aggregation can be compared exactly.
    private func measuredSize(of url: URL) throws -> Int64 {
        let v = try url.resourceValues(forKeys: [
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
        ])
        return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0)
    }

    private func entry(named name: String, in entries: [SpaceLensEntry]) -> SpaceLensEntry? {
        entries.first { $0.name == name }
    }

    // MARK: - Listing, sizing, sorting

    func test_listsImmediateChildrenWithRecursiveTotalsSortedDesc() throws {
        let big = try makeFile("big.bin", bytes: 400_000)
        let small = try makeFile("small.bin", bytes: 20_000)
        let a = try makeFile("dirA/a.bin", bytes: 100_000)
        let b = try makeFile("dirA/sub/b.bin", bytes: 200_000)

        let entries = SpaceLensScanner().scan(root: sandbox)

        XCTAssertEqual(Set(entries.map(\.name)), ["big.bin", "small.bin", "dirA"],
                       "only immediate children are listed — never grandchildren")

        let bigEntry = try XCTUnwrap(entry(named: "big.bin", in: entries))
        XCTAssertEqual(bigEntry.sizeBytes, try measuredSize(of: big))
        XCTAssertFalse(bigEntry.isDirectory)
        XCTAssertNil(bigEntry.itemCount, "plain files carry no item count")

        let dirEntry = try XCTUnwrap(entry(named: "dirA", in: entries))
        XCTAssertTrue(dirEntry.isDirectory)
        XCTAssertFalse(dirEntry.isPackage)
        XCTAssertEqual(dirEntry.sizeBytes, try measuredSize(of: a) + measuredSize(of: b),
                       "directory size is the recursive total of its files")
        XCTAssertEqual(dirEntry.itemCount, 2, "recursive file count (subdirs are not files)")

        _ = small
        XCTAssertEqual(entries, entries.sorted { $0.sizeBytes > $1.sizeBytes },
                       "entries are sorted largest first")
    }

    func test_emptyFolderYieldsNoEntries() {
        XCTAssertEqual(SpaceLensScanner().scan(root: sandbox), [])
    }

    // MARK: - Hidden files

    func test_hiddenFilesAreListedAndCountedInTotals() throws {
        let hiddenRoot = try makeFile(".hiddenRoot", bytes: 50_000)
        let visible = try makeFile("dirB/visible.bin", bytes: 10_000)
        let secret = try makeFile("dirB/.secret", bytes: 60_000)

        let entries = SpaceLensScanner().scan(root: sandbox)

        let hiddenEntry = try XCTUnwrap(entry(named: ".hiddenRoot", in: entries),
                                        "hidden children are real space and must be listed")
        XCTAssertEqual(hiddenEntry.sizeBytes, try measuredSize(of: hiddenRoot))

        let dirEntry = try XCTUnwrap(entry(named: "dirB", in: entries))
        XCTAssertEqual(dirEntry.sizeBytes, try measuredSize(of: visible) + measuredSize(of: secret),
                       "hidden files inside a directory count toward its total")
        XCTAssertEqual(dirEntry.itemCount, 2)
    }

    // MARK: - Symlinks

    func test_symlinksAreNeverFollowed() throws {
        // The scanned root is a subfolder; the big target lives outside it.
        let scanRoot = sandbox.appendingPathComponent("scan")
        try fm.createDirectory(at: scanRoot, withIntermediateDirectories: true)
        let huge = try makeFile("outside/huge.bin", bytes: 500_000)
        let own = try makeFile("scan/dirC/own.bin", bytes: 10_000)

        // A top-level symlink to the big file, and one buried inside a
        // directory pointing at the whole outside folder.
        try fm.createSymbolicLink(
            at: scanRoot.appendingPathComponent("link-to-huge"), withDestinationURL: huge)
        try fm.createSymbolicLink(
            at: scanRoot.appendingPathComponent("dirC/link-to-outside"),
            withDestinationURL: sandbox.appendingPathComponent("outside"))

        let entries = SpaceLensScanner().scan(root: scanRoot)

        let linkEntry = try XCTUnwrap(entry(named: "link-to-huge", in: entries))
        XCTAssertEqual(linkEntry.sizeBytes, 0, "a symlink counts as ~0, never its target")
        XCTAssertFalse(linkEntry.isDirectory)

        let dirEntry = try XCTUnwrap(entry(named: "dirC", in: entries))
        XCTAssertEqual(dirEntry.sizeBytes, try measuredSize(of: own),
                       "a symlinked directory inside the walk is never traversed")
        XCTAssertEqual(dirEntry.itemCount, 1)

        let total = entries.reduce(Int64(0)) { $0 + $1.sizeBytes }
        XCTAssertLessThan(total, try measuredSize(of: huge),
                          "the outside target's bytes never leak into the totals")
    }

    // MARK: - Packages

    func test_packageDirectoryIsSizedAsALeaf() throws {
        let payload = try makeFile("Bundle.app/Contents/payload.bin", bytes: 120_000)

        let entries = SpaceLensScanner().scan(root: sandbox)
        let pkg = try XCTUnwrap(entry(named: "Bundle.app", in: entries))

        XCTAssertTrue(pkg.isPackage, "a .app directory is marked as a package")
        XCTAssertTrue(pkg.isDirectory)
        XCTAssertEqual(pkg.sizeBytes, try measuredSize(of: payload),
                       "packages are still sized in full")
        XCTAssertEqual(pkg.itemCount, 1)
    }

    func test_packageDetectionHelper() throws {
        let app = sandbox.appendingPathComponent("Fake.app")
        let plain = sandbox.appendingPathComponent("Plain")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        try fm.createDirectory(at: plain, withIntermediateDirectories: true)

        XCTAssertTrue(SpaceLensScanner.isPackage(app))
        XCTAssertFalse(SpaceLensScanner.isPackage(plain))
    }

    // MARK: - Errors and cancellation

    func test_unreadableRootReportsGracefully() {
        let missing = sandbox.appendingPathComponent("does-not-exist")

        XCTAssertEqual(SpaceLensScanner().scan(root: missing), [])

        var sawUnreadable = false
        SpaceLensScanner().scanIncremental(root: missing) { event in
            if case .rootUnreadable = event { sawUnreadable = true }
        }
        XCTAssertTrue(sawUnreadable, "an unlistable root is reported, not thrown")
    }

    func test_cancellationStopsTheWalkEarly() async throws {
        for i in 0..<200 {
            try makeFile("f\(i).dat", bytes: 64)
        }
        let root: URL = sandbox

        // Cancel the walking task from inside the first entry event; the
        // scanner's cooperative check must stop it before the next child.
        let seen = await Task.detached {
            var count = 0
            SpaceLensScanner().scanIncremental(root: root) { event in
                if case .entry = event {
                    count += 1
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
            return count
        }.value

        XCTAssertEqual(seen, 1, "the walk stops at the first child after cancellation")
    }
}
