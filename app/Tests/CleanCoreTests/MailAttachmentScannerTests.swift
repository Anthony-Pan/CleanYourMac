import XCTest
@testable import CleanCore

/// Exercises the Mail Downloads scanner against a sandbox — never the user's
/// real Mail folders. Uses the shared `RecordingDisposer` so nothing ever
/// lands in the real Trash.
final class MailAttachmentScannerTests: XCTestCase {
    var sandbox: URL!
    /// Stand-ins for the two fixed Mail Downloads roots.
    var modernRoot: URL!
    var legacyRoot: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cym-mail-\(UUID().uuidString)")
        modernRoot = sandbox.appendingPathComponent("Container/Mail Downloads")
        legacyRoot = sandbox.appendingPathComponent("Legacy Mail Downloads")
        try fm.createDirectory(at: modernRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: sandbox)
    }

    private func makeScanner(disposer: FileDisposer = RecordingDisposer()) -> MailAttachmentScanner {
        MailAttachmentScanner(roots: [modernRoot, legacyRoot], disposer: disposer)
    }

    private func makeFile(_ url: URL, bytes: Int) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: url.path, contents: Data(repeating: 0x41, count: bytes)))
    }

    // MARK: - Scanning

    func test_scanFindsNestedFilesWithSizes_largestFirst() throws {
        try makeFile(modernRoot.appendingPathComponent("report.pdf"), bytes: 10_000)
        try makeFile(modernRoot.appendingPathComponent("Message Attachments/deck.key"), bytes: 50_000)
        try makeFile(legacyRoot.appendingPathComponent("photo.jpg"), bytes: 2_000)

        let result = makeScanner().scan()

        XCTAssertFalse(result.accessDenied)
        XCTAssertEqual(result.attachments.count, 3, "all regular files under both roots are found")
        let names = result.attachments.map(\.name)
        XCTAssertEqual(names, ["deck.key", "report.pdf", "photo.jpg"], "sorted largest first")
        for attachment in result.attachments {
            // Allocated size is block-rounded, so it is at least the written bytes.
            XCTAssertGreaterThanOrEqual(attachment.sizeBytes, 2_000)
            XCTAssertNotNil(attachment.modificationDate)
        }
        XCTAssertGreaterThanOrEqual(result.totalBytes, 62_000)
    }

    func test_scanListsOnlyRegularFiles_notDirectories() throws {
        try makeFile(modernRoot.appendingPathComponent("Sub/inner.txt"), bytes: 500)

        let result = makeScanner().scan()

        XCTAssertEqual(result.attachments.map(\.name), ["inner.txt"],
                       "the containing directory itself is never listed")
    }

    func test_scanSkipsSymlinks_andFilesTheyPointTo() throws {
        // A file outside the roots plus two links planted inside: one to the
        // outside file, one directory link. Neither may surface in results.
        let secret = sandbox.appendingPathComponent("secret.txt")
        try makeFile(secret, bytes: 9_000)
        let secretDir = sandbox.appendingPathComponent("SecretDir")
        try makeFile(secretDir.appendingPathComponent("nested.txt"), bytes: 9_000)

        try fm.createSymbolicLink(at: modernRoot.appendingPathComponent("escape.txt"),
                                  withDestinationURL: secret)
        try fm.createSymbolicLink(at: modernRoot.appendingPathComponent("escapeDir"),
                                  withDestinationURL: secretDir)
        try makeFile(modernRoot.appendingPathComponent("real.txt"), bytes: 100)

        let result = makeScanner().scan()

        XCTAssertEqual(result.attachments.map(\.name), ["real.txt"],
                       "symlinks and anything behind them are skipped")
        XCTAssertTrue(fm.fileExists(atPath: secret.path))
    }

    func test_missingRootDoesNotCrashAndReportsCleanly() {
        let missing = sandbox.appendingPathComponent("Nowhere/Mail Downloads")
        let scanner = MailAttachmentScanner(roots: [missing], disposer: RecordingDisposer())

        let result = scanner.scan()

        XCTAssertTrue(result.attachments.isEmpty)
        XCTAssertFalse(result.accessDenied, "an absent root is normal, not an access problem")
    }

    func test_unreadableRootSetsAccessDenied() throws {
        try makeFile(legacyRoot.appendingPathComponent("visible.txt"), bytes: 300)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: modernRoot.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: modernRoot.path) }

        let result = makeScanner().scan()

        XCTAssertTrue(result.accessDenied, "an existing-but-unlistable root flags access denied")
        XCTAssertEqual(result.attachments.map(\.name), ["visible.txt"],
                       "the readable root is still scanned")
    }

    func test_scanStopsEarlyWhenAskedTo() throws {
        try makeFile(modernRoot.appendingPathComponent("a.txt"), bytes: 100)
        try makeFile(modernRoot.appendingPathComponent("b.txt"), bytes: 100)

        let result = makeScanner().scan(shouldContinue: { false })

        XCTAssertTrue(result.attachments.isEmpty, "a stopped walk returns without scanning further")
    }

    // MARK: - Removal safety

    func test_removeMovesOnlySelectedItems() throws {
        try makeFile(modernRoot.appendingPathComponent("keep.pdf"), bytes: 1_000)
        try makeFile(modernRoot.appendingPathComponent("toss.pdf"), bytes: 1_000)
        try makeFile(legacyRoot.appendingPathComponent("toss2.pdf"), bytes: 1_000)

        let disposer = RecordingDisposer()
        let scanner = makeScanner(disposer: disposer)
        let all = scanner.scan().attachments
        let selected = all.filter { $0.name != "keep.pdf" }

        let report = scanner.remove(selected, dryRun: false)

        XCTAssertEqual(report.trashed.count, 2)
        XCTAssertTrue(report.blocked.isEmpty)
        XCTAssertTrue(report.failed.isEmpty)
        XCTAssertEqual(disposer.disposed.count, 2)
        XCTAssertTrue(fm.fileExists(atPath: modernRoot.appendingPathComponent("keep.pdf").path),
                      "the unselected file must survive")
        XCTAssertFalse(fm.fileExists(atPath: modernRoot.appendingPathComponent("toss.pdf").path))
    }

    func test_dryRunRemovesNothing() throws {
        try makeFile(modernRoot.appendingPathComponent("doc.pdf"), bytes: 4_000)

        let disposer = RecordingDisposer()
        let scanner = makeScanner(disposer: disposer)
        let found = scanner.scan().attachments

        let report = scanner.remove(found, dryRun: true)

        XCTAssertTrue(disposer.disposed.isEmpty, "dry run must not dispose anything")
        XCTAssertGreaterThan(report.freedBytes, 0, "dry run still reports would-be freed space")
        XCTAssertTrue(fm.fileExists(atPath: modernRoot.appendingPathComponent("doc.pdf").path))
    }

    /// THE key safety test: a hand-crafted attachment pointing outside the
    /// fixed roots must be refused by the policy, never touched.
    func test_removeRejectsPathsOutsideTheRoots() throws {
        let important = sandbox.appendingPathComponent("Documents/important.txt")
        try makeFile(important, bytes: 100)

        let bogus = MailAttachment(url: important, sizeBytes: 100, modificationDate: nil)
        let disposer = RecordingDisposer()
        let report = makeScanner(disposer: disposer).remove([bogus], dryRun: false)

        XCTAssertTrue(disposer.disposed.isEmpty, "must not dispose an out-of-scope item")
        XCTAssertEqual(report.blocked.count, 1)
        XCTAssertEqual(report.blocked.first?.reason, .outsideAllowedRoots)
        XCTAssertTrue(fm.fileExists(atPath: important.path), "the outside file must survive")
    }

    func test_policyRefusesTheRootsThemselves() {
        let scanner = makeScanner()
        XCTAssertEqual(scanner.policy.validate(modernRoot)?.reason, .isAllowedRootItself)
        XCTAssertEqual(scanner.policy.validate(legacyRoot)?.reason, .isAllowedRootItself)
    }

    // MARK: - Declarative roots

    func test_defaultRootsAreTheFixedMailLocations() {
        let paths = MailAttachmentScanner.defaultRoots.map(\.path)
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths[0].hasSuffix("Library/Containers/com.apple.mail/Data/Library/Mail Downloads"))
        XCTAssertTrue(paths[1].hasSuffix("Library/Mail Downloads"))
    }
}
