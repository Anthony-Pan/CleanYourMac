import XCTest
@testable import CleanCore

/// A disposer that records what it was asked to remove and simulates trashing
/// by deleting inside the test sandbox — so tests are deterministic and never
/// depend on the real Trash.
final class RecordingDisposer: FileDisposer, @unchecked Sendable {
    private(set) var disposed: [URL] = []
    func dispose(_ url: URL) throws {
        disposed.append(url)
        try FileManager.default.removeItem(at: url)
    }
}

final class ScannerCleanerTests: XCTestCase {
    var sandbox: URL!
    var caches: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cym-\(UUID().uuidString)")
        caches = sandbox.appendingPathComponent("Caches")
        try fm.createDirectory(at: caches, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: sandbox)
    }

    private func makeFile(_ url: URL, bytes: Int) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: url.path, contents: Data(repeating: 0x41, count: bytes)))
    }

    private func testCategory() -> CleanupCategory {
        CleanupCategory(id: "t", nameEN: "Test", nameCN: "测试",
                        targets: [CleanupTarget(path: caches.path)])
    }

    private func makePolicy() -> SafetyPolicy { SafetyPolicy(allowedRoots: [caches]) }

    func test_scanFindsImmediateChildrenWithNonZeroSize() throws {
        try makeFile(caches.appendingPathComponent("AppA/data.bin"), bytes: 5_000)
        try makeFile(caches.appendingPathComponent("appB.log"), bytes: 2_000)

        let group = Scanner(policy: makePolicy()).scan(category: testCategory())
        XCTAssertEqual(group.items.count, 2)
        XCTAssertGreaterThan(group.totalBytes, 0)
    }

    func test_dryRunDeletesNothing() throws {
        try makeFile(caches.appendingPathComponent("AppA/data.bin"), bytes: 5_000)
        let group = Scanner(policy: makePolicy()).scan(category: testCategory())

        let disposer = RecordingDisposer()
        let report = Cleaner(policy: makePolicy(), disposer: disposer).clean(group.items, dryRun: true)

        XCTAssertTrue(disposer.disposed.isEmpty, "dry run must not dispose anything")
        XCTAssertGreaterThan(report.freedBytes, 0, "dry run still reports would-be freed space")
        for item in group.items {
            XCTAssertTrue(fm.fileExists(atPath: item.path), "file must still exist after dry run")
        }
    }

    func test_realCleanDisposesOnlyViaDisposer() throws {
        try makeFile(caches.appendingPathComponent("AppA/data.bin"), bytes: 5_000)
        try makeFile(caches.appendingPathComponent("appB.log"), bytes: 2_000)
        let group = Scanner(policy: makePolicy()).scan(category: testCategory())

        let disposer = RecordingDisposer()
        let report = Cleaner(policy: makePolicy(), disposer: disposer).clean(group.items, dryRun: false)

        XCTAssertEqual(disposer.disposed.count, group.items.count)
        XCTAssertEqual(report.trashed.count, group.items.count)
        XCTAssertTrue(report.failed.isEmpty)
        for item in group.items {
            XCTAssertFalse(fm.fileExists(atPath: item.path), "cleaned item should be gone from origin")
        }
    }

    /// THE key safety test: even if a bogus/hand-crafted item points OUTSIDE the
    /// allowed roots (a bug upstream, a stale scan, a crafted filename), the
    /// cleaner must refuse to touch it.
    func test_cleanerRefusesUnsafeItemAndLeavesFileIntact() throws {
        let important = sandbox.appendingPathComponent("Documents/important.txt")
        try makeFile(important, bytes: 100)

        let bogus = ScanItem(url: important, categoryID: "t", sizeBytes: 100, modificationDate: nil)
        let disposer = RecordingDisposer()
        let report = Cleaner(policy: makePolicy(), disposer: disposer).clean([bogus], dryRun: false)

        XCTAssertTrue(disposer.disposed.isEmpty, "must not dispose an out-of-scope item")
        XCTAssertEqual(report.blocked.count, 1)
        XCTAssertEqual(report.blocked.first?.reason, .outsideAllowedRoots)
        XCTAssertTrue(fm.fileExists(atPath: important.path), "the important file must survive")
    }

    func test_ageFilterKeepsRecentFiles() throws {
        let old = caches.appendingPathComponent("old.log")
        let recent = caches.appendingPathComponent("recent.log")
        try makeFile(old, bytes: 1_000)
        try makeFile(recent, bytes: 1_000)
        // Backdate `old` by 100 days.
        let hundredDaysAgo = Date(timeIntervalSinceNow: -100 * 86_400)
        try fm.setAttributes([.modificationDate: hundredDaysAgo], ofItemAtPath: old.path)

        let category = CleanupCategory(id: "t", nameEN: "Test", nameCN: "测试",
                                       targets: [CleanupTarget(path: caches.path, minAgeDays: 30)])
        let group = Scanner(policy: makePolicy()).scan(category: category)

        let names = Set(group.items.map { $0.url.lastPathComponent })
        XCTAssertTrue(names.contains("old.log"))
        XCTAssertFalse(names.contains("recent.log"), "files newer than the age threshold are kept")
    }
}
