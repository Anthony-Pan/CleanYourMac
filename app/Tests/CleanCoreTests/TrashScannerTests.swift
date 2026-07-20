import XCTest
@testable import CleanCore

/// Trash Bins core logic: scanning a (sandboxed) trash directory and
/// permanently removing the reviewed selection. Everything lives under
/// NSTemporaryDirectory() — real user data is never touched.
final class TrashScannerTests: XCTestCase {
    var sandbox: URL!
    var trash: URL!
    var outside: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cym-trash-\(UUID().uuidString)")
        trash = sandbox.appendingPathComponent("Trash")
        outside = sandbox.appendingPathComponent("Outside")
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: sandbox)
    }

    @discardableResult
    private func makeFile(_ url: URL, bytes: Int) throws -> URL {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: url.path, contents: Data(repeating: 0x61, count: bytes)))
        return url
    }

    private func item(named name: String, in items: [TrashItem]) -> TrashItem? {
        items.first { $0.name == name }
    }

    // MARK: - Scan

    func test_scanListsTopLevelItemsOnly() throws {
        try makeFile(trash.appendingPathComponent("report.pdf"), bytes: 100)
        try makeFile(trash.appendingPathComponent("Project/src/main.swift"), bytes: 100)
        try makeFile(trash.appendingPathComponent("notes.txt"), bytes: 100)

        let items = TrashScanner(trashRoot: trash).scan()
        XCTAssertEqual(Set(items.map(\.name)), ["report.pdf", "Project", "notes.txt"],
                       "each thing thrown away is exactly one row")
        XCTAssertFalse(items.contains { $0.name == "main.swift" },
                       "nested files belong to their folder, not the top level")
        XCTAssertEqual(item(named: "Project", in: items)?.isDirectory, true)
        XCTAssertEqual(item(named: "report.pdf", in: items)?.isDirectory, false)
    }

    func test_directorySizesAreRecursive() throws {
        try makeFile(trash.appendingPathComponent("Bundle/a.bin"), bytes: 10_000)
        try makeFile(trash.appendingPathComponent("Bundle/nested/deep/b.bin"), bytes: 20_000)

        let items = TrashScanner(trashRoot: trash).scan()
        let bundle = try XCTUnwrap(item(named: "Bundle", in: items))
        XCTAssertGreaterThanOrEqual(bundle.sizeBytes, 30_000,
                                    "recursive size must cover files at every depth")
        // Same sizing convention as everywhere else in the app.
        XCTAssertEqual(bundle.sizeBytes, Scanner.allocatedSize(of: trash.appendingPathComponent("Bundle")))
    }

    func test_scanSortsLargestFirstAndExposesTotal() throws {
        try makeFile(trash.appendingPathComponent("small.txt"), bytes: 50)
        try makeFile(trash.appendingPathComponent("big.bin"), bytes: 200_000)
        try makeFile(trash.appendingPathComponent("mid.bin"), bytes: 40_000)

        let items = TrashScanner(trashRoot: trash).scan()
        XCTAssertEqual(items.map(\.name), ["big.bin", "mid.bin", "small.txt"])
        XCTAssertEqual(items.totalBytes, items.reduce(0) { $0 + $1.sizeBytes })
        XCTAssertGreaterThanOrEqual(items.totalBytes, 240_050)
    }

    func test_scanSkipsFinderMetadataAndHandlesMissingRoot() throws {
        try makeFile(trash.appendingPathComponent(".DS_Store"), bytes: 10)
        try makeFile(trash.appendingPathComponent("real.txt"), bytes: 10)

        let items = TrashScanner(trashRoot: trash).scan()
        XCTAssertEqual(items.map(\.name), ["real.txt"])

        let missing = TrashScanner(trashRoot: sandbox.appendingPathComponent("NoSuchTrash"))
        XCTAssertEqual(missing.scan(), [], "a missing trash directory yields an empty result, not a crash")
    }

    func test_scanReportsEachItemForLiveProgress() throws {
        try makeFile(trash.appendingPathComponent("a.txt"), bytes: 10)
        try makeFile(trash.appendingPathComponent("b.txt"), bytes: 10)

        var streamed: [String] = []
        let items = TrashScanner(trashRoot: trash).scan { streamed.append($0.name) }
        XCTAssertEqual(Set(streamed), Set(items.map(\.name)),
                       "every item is announced exactly once while scanning")
        XCTAssertEqual(streamed.count, items.count)
    }

    func test_symlinkToOutsideDirectoryIsNeverFollowedWhenSizing() throws {
        try makeFile(outside.appendingPathComponent("Payload/huge.bin"), bytes: 1_000_000)
        let link = trash.appendingPathComponent("dirlink")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside.appendingPathComponent("Payload"))

        let items = TrashScanner(trashRoot: trash).scan()
        let dirlink = try XCTUnwrap(item(named: "dirlink", in: items))
        XCTAssertFalse(dirlink.isDirectory, "a link is described as the link itself, not its target")
        XCTAssertLessThan(dirlink.sizeBytes, 1_000_000,
                          "sizing must never follow the link into its target")
    }

    // MARK: - Remove

    func test_removeDeletesExactlyTheSelectedItems() throws {
        try makeFile(trash.appendingPathComponent("keep.txt"), bytes: 10)
        try makeFile(trash.appendingPathComponent("goA.txt"), bytes: 10)
        try makeFile(trash.appendingPathComponent("goB/inner.txt"), bytes: 10)

        let items = TrashScanner(trashRoot: trash).scan()
        let targets = items.filter { $0.name != "keep.txt" }
        let report = TrashRemover(trashRoot: trash).remove(targets)

        XCTAssertEqual(Set(report.removed), Set(targets.map(\.path)))
        XCTAssertTrue(report.blocked.isEmpty)
        XCTAssertTrue(report.failed.isEmpty)
        XCTAssertEqual(report.freedBytes, targets.reduce(0) { $0 + $1.sizeBytes })
        XCTAssertTrue(fm.fileExists(atPath: trash.appendingPathComponent("keep.txt").path),
                      "unselected items must survive")
        XCTAssertFalse(fm.fileExists(atPath: trash.appendingPathComponent("goA.txt").path))
        XCTAssertFalse(fm.fileExists(atPath: trash.appendingPathComponent("goB").path))
    }

    func test_symlinkEscapingTheTrashIsBlockedAndItsTargetSurvives() throws {
        let secret = try makeFile(outside.appendingPathComponent("secret.txt"), bytes: 10)
        let link = trash.appendingPathComponent("escape")
        try fm.createSymbolicLink(at: link, withDestinationURL: secret)

        let items = TrashScanner(trashRoot: trash).scan()
        let escape = try XCTUnwrap(item(named: "escape", in: items))

        let report = TrashRemover(trashRoot: trash).remove([escape])
        XCTAssertEqual(report.blocked.map(\.reason), [.outsideAllowedRoots],
                       "a link resolving outside the Trash must be refused, never followed")
        XCTAssertTrue(report.removed.isEmpty)
        XCTAssertEqual(report.freedBytes, 0)
        XCTAssertTrue(fm.fileExists(atPath: secret.path),
                      "the file outside the Trash must survive")
    }

    func test_pathsOutsideTheRootAreBlocked() throws {
        let secret = try makeFile(outside.appendingPathComponent("document.txt"), bytes: 10)
        let forged = TrashItem(url: secret, sizeBytes: 10, modificationDate: nil, isDirectory: false)

        let report = TrashRemover(trashRoot: trash).remove([forged])
        XCTAssertEqual(report.blocked.map(\.reason), [.outsideAllowedRoots])
        XCTAssertTrue(report.removed.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: secret.path))
    }

    func test_trashRootItselfIsNeverDeleted() {
        let root = TrashItem(url: trash, sizeBytes: 0, modificationDate: nil, isDirectory: true)
        let report = TrashRemover(trashRoot: trash).remove([root])

        XCTAssertEqual(report.blocked.map(\.reason), [.isAllowedRootItself])
        var isDir: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: trash.path, isDirectory: &isDir) && isDir.boolValue,
                      "the Trash directory itself must survive")
    }

    func test_reportTalliesAreAccurateAcrossMixedOutcomes() throws {
        let good = try makeFile(trash.appendingPathComponent("good.txt"), bytes: 10)
        let items = TrashScanner(trashRoot: trash).scan()
        let goodItem = try XCTUnwrap(item(named: "good.txt", in: items))

        // Outside the root -> blocked; inside but nonexistent -> failed.
        let forged = TrashItem(url: outside.appendingPathComponent("nope.txt"),
                               sizeBytes: 99, modificationDate: nil, isDirectory: false)
        let ghost = TrashItem(url: trash.appendingPathComponent("vanished.txt"),
                              sizeBytes: 42, modificationDate: nil, isDirectory: false)

        let report = TrashRemover(trashRoot: trash).remove([goodItem, forged, ghost])
        XCTAssertEqual(report.removed, [goodItem.path])
        XCTAssertEqual(report.blocked.count, 1)
        XCTAssertEqual(report.failed.count, 1)
        XCTAssertEqual(report.freedBytes, goodItem.sizeBytes,
                       "freed bytes count only what was actually removed")
        XCTAssertFalse(fm.fileExists(atPath: good.path))
    }

    // MARK: - Bin discovery

    /// A temp directory posing as a mounted volume, optionally with the
    /// `.Trashes/<uid>` directory the discovery rule looks for.
    private func makeVolume(_ name: String, withBin: Bool) throws -> (volume: TrashBinDiscovery.Volume, bin: URL) {
        let vol = sandbox.appendingPathComponent("Volumes/\(name)")
        let bin = vol.appendingPathComponent(".Trashes/\(getuid())")
        try fm.createDirectory(at: withBin ? bin : vol, withIntermediateDirectories: true)
        return (TrashBinDiscovery.Volume(url: vol, name: name), bin)
    }

    func test_discoveryFollowsTheFixedRule() throws {
        let (volA, binA) = try makeVolume("Backup HD", withBin: true)
        let (volB, _) = try makeVolume("Bare Stick", withBin: false)

        let bins = TrashBinDiscovery(userTrashRoot: trash) { [volA, volB] }.discoverBins()

        XCTAssertEqual(bins.map(\.root.path), [trash.path, binA.path],
                       "roots come only from the rule — user Trash plus <volume>/.Trashes/<uid>; a volume without that dir has no bin")
        XCTAssertEqual(bins.map(\.displayName), ["User Trash", "Backup HD"])
        XCTAssertEqual(bins.map(\.isUserTrash), [true, false])
        XCTAssertTrue(bins.allSatisfy(\.isAccessible))
    }

    func test_missingUserTrashIsAnEmptyBinNotAnInaccessibleOne() {
        let missing = sandbox.appendingPathComponent("NoTrashHere")
        let bins = TrashBinDiscovery(userTrashRoot: missing) { [] }.discoverBins()

        XCTAssertEqual(bins.map(\.isUserTrash), [true], "the user's bin is always present")
        XCTAssertTrue(bins[0].isAccessible,
                      "nothing there to fail on — scanning yields an honest zero")
        XCTAssertEqual(TrashScanner.scanBins(bins), [])
    }

    func test_unlistableBinIsSurfacedAsInaccessibleNeverDropped() throws {
        let (vol, bin) = try makeVolume("Locked", withBin: true)
        try makeFile(bin.appendingPathComponent("unreachable.txt"), bytes: 10)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: bin.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bin.path) }

        let bins = TrashBinDiscovery(userTrashRoot: trash) { [vol] }.discoverBins()
        let locked = try XCTUnwrap(bins.first { $0.displayName == "Locked" },
                                   "an unlistable bin must stay in the list")
        XCTAssertFalse(locked.isAccessible)

        XCTAssertEqual(TrashScanner.scanBins(bins), [],
                       "scanning skips the unreadable bin instead of failing — the UI surfaces it via isAccessible")
    }

    func test_defaultVolumeProviderExcludesTheBootVolume() {
        XCTAssertFalse(TrashBinDiscovery.mountedNonBootVolumes().contains { $0.url.path == "/" },
                       "the boot volume's trash is the user's Trash, handled separately")
    }

    // MARK: - Multi-bin scan

    func test_multiBinScanTagsEveryItemWithItsBin() throws {
        let (vol, bin) = try makeVolume("Backup HD", withBin: true)
        try makeFile(trash.appendingPathComponent("user-file.txt"), bytes: 5_000)
        try makeFile(bin.appendingPathComponent("volume-file.bin"), bytes: 90_000)
        try makeFile(bin.appendingPathComponent("clip.mov"), bytes: 40_000)

        let bins = TrashBinDiscovery(userTrashRoot: trash) { [vol] }.discoverBins()
        var streamed = 0
        let items = TrashScanner.scanBins(bins) { _ in streamed += 1 }

        XCTAssertEqual(items.map(\.name), ["volume-file.bin", "clip.mov", "user-file.txt"],
                       "one flat list, largest first, across every bin")
        XCTAssertEqual(streamed, 3, "per-item streaming covers every bin")
        XCTAssertEqual(items.first { $0.name == "user-file.txt" }?.binID, trash.path)
        XCTAssertEqual(Set(items.filter { $0.binID == bin.path }.map(\.name)),
                       ["volume-file.bin", "clip.mov"],
                       "each item is tagged with the bin it was found in, for grouping")
    }

    // MARK: - Multi-bin removal

    func test_removerAcceptsEveryBinAndRefusesEverythingOutside() throws {
        let (vol, bin) = try makeVolume("Backup HD", withBin: true)
        try makeFile(trash.appendingPathComponent("in-user.txt"), bytes: 10)
        try makeFile(bin.appendingPathComponent("in-volume.txt"), bytes: 10)
        let secret = try makeFile(outside.appendingPathComponent("secret.txt"), bytes: 10)

        let bins = TrashBinDiscovery(userTrashRoot: trash) { [vol] }.discoverBins()
        let items = TrashScanner.scanBins(bins)
        let forged = TrashItem(url: secret, sizeBytes: 10, modificationDate: nil, isDirectory: false)

        let report = TrashRemover(binRoots: bins.map(\.root)).remove(items + [forged])

        XCTAssertEqual(Set(report.removed), Set(items.map(\.path)),
                       "items inside any discovered bin are removable")
        XCTAssertEqual(report.blocked.map(\.reason), [.outsideAllowedRoots],
                       "anything outside every bin root is refused")
        XCTAssertTrue(fm.fileExists(atPath: secret.path))
        XCTAssertFalse(fm.fileExists(atPath: trash.appendingPathComponent("in-user.txt").path))
        XCTAssertFalse(fm.fileExists(atPath: bin.appendingPathComponent("in-volume.txt").path))
    }

    func test_removerRefusesEachBinRootItself() throws {
        let (vol, bin) = try makeVolume("Backup HD", withBin: true)
        let bins = TrashBinDiscovery(userTrashRoot: trash) { [vol] }.discoverBins()
        let remover = TrashRemover(binRoots: bins.map(\.root))

        let roots = bins.map {
            TrashItem(url: $0.root, sizeBytes: 0, modificationDate: nil, isDirectory: true)
        }
        let report = remover.remove(roots)

        XCTAssertEqual(report.blocked.map(\.reason), [.isAllowedRootItself, .isAllowedRootItself],
                       "each bin root may only ever have its contents removed, never itself")
        XCTAssertTrue(report.removed.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: trash.path))
        XCTAssertTrue(fm.fileExists(atPath: bin.path))
    }

    func test_symlinkEscapingAVolumeBinIsBlocked() throws {
        let (vol, bin) = try makeVolume("Backup HD", withBin: true)
        let secret = try makeFile(outside.appendingPathComponent("vault.txt"), bytes: 10)
        try fm.createSymbolicLink(at: bin.appendingPathComponent("escape"),
                                  withDestinationURL: secret)

        let bins = TrashBinDiscovery(userTrashRoot: trash) { [vol] }.discoverBins()
        let items = TrashScanner.scanBins(bins)
        let escape = try XCTUnwrap(item(named: "escape", in: items))

        let report = TrashRemover(binRoots: bins.map(\.root)).remove([escape])
        XCTAssertEqual(report.blocked.map(\.reason), [.outsideAllowedRoots],
                       "symlink-escape protection applies to volume bins exactly as to the user's Trash")
        XCTAssertTrue(fm.fileExists(atPath: secret.path))
    }
}
