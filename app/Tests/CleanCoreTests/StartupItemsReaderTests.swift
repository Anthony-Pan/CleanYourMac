import XCTest
@testable import CleanCore

/// Tests for the read-only startup-items reader. All fixture plists live in a
/// temp sandbox — the reader is pointed at injected directories and never sees
/// the real launchd folders.
final class StartupItemsReaderTests: XCTestCase {
    var sandbox: URL!
    var userAgents: URL!
    var systemAgents: URL!
    var systemDaemons: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cym-startup-\(UUID().uuidString)")
        userAgents = sandbox.appendingPathComponent("Library/LaunchAgents")
        systemAgents = sandbox.appendingPathComponent("SystemLibrary/LaunchAgents")
        systemDaemons = sandbox.appendingPathComponent("SystemLibrary/LaunchDaemons")
        for dir in [userAgents!, systemAgents!, systemDaemons!] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: sandbox)
    }

    // MARK: - Fixtures

    private func reader() -> StartupItemsReader {
        StartupItemsReader(locations: [
            .init(directory: userAgents, kind: .userAgent),
            .init(directory: systemAgents, kind: .systemAgent),
            .init(directory: systemDaemons, kind: .systemDaemon),
        ])
    }

    @discardableResult
    private func writePlist(_ dict: [String: Any], named name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: url)
        return url
    }

    // MARK: - Field extraction

    func test_programVariantExtractsAllFields() throws {
        let url = try writePlist([
            "Label": "com.acme.updater",
            "Program": "/usr/local/bin/acme-updater",
            "RunAtLoad": true,
            "Disabled": false,
        ], named: "com.acme.updater.plist", in: userAgents)

        let report = reader().read()
        XCTAssertEqual(report.unreadableCount, 0)
        XCTAssertEqual(report.items.count, 1)
        let item = try XCTUnwrap(report.items.first)
        XCTAssertEqual(item.label, "com.acme.updater")
        XCTAssertEqual(item.kind, .userAgent)
        XCTAssertEqual(item.executable, "/usr/local/bin/acme-updater")
        XCTAssertEqual(item.runAtLoad, true)
        XCTAssertEqual(item.disabled, false)
        XCTAssertFalse(item.isApple)
        // The listing may resolve /var → /private/var; compare canonical forms.
        XCTAssertEqual(item.url.canonicalized, url.canonicalized)
        XCTAssertEqual(item.id, item.url.path, "items are identified by their plist path")
    }

    func test_programArgumentsFirstElementIsExecutable() throws {
        try writePlist([
            "Label": "com.acme.helperd",
            "ProgramArguments": ["/Library/Acme/helperd", "--daemon", "-v"],
        ], named: "com.acme.helperd.plist", in: systemDaemons)

        let item = try XCTUnwrap(reader().read().items.first)
        XCTAssertEqual(item.executable, "/Library/Acme/helperd")
        XCTAssertEqual(item.kind, .systemDaemon)
        XCTAssertNil(item.runAtLoad, "missing RunAtLoad stays nil, never a fake false")
        XCTAssertNil(item.disabled)
    }

    func test_programWinsOverProgramArguments() throws {
        // launchd prefers Program when both keys are present.
        try writePlist([
            "Label": "com.acme.both",
            "Program": "/Library/Acme/main",
            "ProgramArguments": ["/Library/Acme/other", "--flag"],
        ], named: "com.acme.both.plist", in: systemAgents)

        let item = try XCTUnwrap(reader().read().items.first)
        XCTAssertEqual(item.executable, "/Library/Acme/main")
    }

    func test_missingLabelFallsBackToFilename() throws {
        try writePlist(["RunAtLoad": true], named: "com.acme.nolabel.plist", in: systemAgents)

        let item = try XCTUnwrap(reader().read().items.first)
        XCTAssertEqual(item.label, "com.acme.nolabel")
        XCTAssertNil(item.executable)
    }

    // MARK: - Apple detection

    func test_appleDetectedByLabelOrFilenamePrefix() throws {
        try writePlist(["Label": "com.apple.SafariHistoryService"],
                       named: "com.apple.SafariHistoryService.plist", in: userAgents)
        try writePlist(["Label": "com.vendor.shim"],
                       named: "com.apple.vendor-shim.plist", in: userAgents)
        try writePlist(["Label": "com.notapple.tool"],
                       named: "com.notapple.tool.plist", in: userAgents)

        let items = reader().read().items
        func item(_ label: String) throws -> StartupItem {
            try XCTUnwrap(items.first { $0.label == label })
        }
        XCTAssertTrue(try item("com.apple.SafariHistoryService").isApple, "Apple label prefix")
        XCTAssertTrue(try item("com.vendor.shim").isApple, "Apple filename prefix")
        XCTAssertFalse(try item("com.notapple.tool").isApple)
    }

    // MARK: - Malformed / missing inputs

    func test_malformedPlistIsCountedAndSkipped() throws {
        try Data("this is not a plist".utf8)
            .write(to: userAgents.appendingPathComponent("broken.plist"))
        // A valid plist whose top level is not a dictionary is also unreadable
        // for our purposes.
        let arrayPlist = try PropertyListSerialization.data(
            fromPropertyList: ["a", "b"], format: .xml, options: 0)
        try arrayPlist.write(to: userAgents.appendingPathComponent("array.plist"))
        try writePlist(["Label": "com.acme.good"], named: "com.acme.good.plist", in: userAgents)

        let report = reader().read()
        XCTAssertEqual(report.unreadableCount, 2)
        XCTAssertEqual(report.items.map(\.label), ["com.acme.good"],
                       "the healthy plist still parses; the broken ones are skipped")
    }

    func test_missingDirectoryYieldsEmptyResult() {
        let gone = sandbox.appendingPathComponent("does-not-exist/LaunchAgents")
        let report = StartupItemsReader(
            locations: [.init(directory: gone, kind: .userAgent)]
        ).read()
        XCTAssertTrue(report.items.isEmpty)
        XCTAssertEqual(report.unreadableCount, 0, "a missing directory is not an error")
    }

    func test_nonPlistFilesAreIgnored() throws {
        try Data("readme".utf8).write(to: userAgents.appendingPathComponent("README.txt"))
        try fm.createDirectory(at: userAgents.appendingPathComponent("Subfolder"),
                               withIntermediateDirectories: true)

        let report = reader().read()
        XCTAssertTrue(report.items.isEmpty)
        XCTAssertEqual(report.unreadableCount, 0, "non-plist entries are out of scope, not errors")
    }

    // MARK: - Kind mapping

    func test_kindFollowsTheDirectoryTheItemWasFoundIn() throws {
        try writePlist(["Label": "com.acme.a"], named: "a.plist", in: userAgents)
        try writePlist(["Label": "com.acme.b"], named: "b.plist", in: systemAgents)
        try writePlist(["Label": "com.acme.c"], named: "c.plist", in: systemDaemons)

        let byLabel = Dictionary(uniqueKeysWithValues: reader().read().items.map { ($0.label, $0.kind) })
        XCTAssertEqual(byLabel["com.acme.a"], .userAgent)
        XCTAssertEqual(byLabel["com.acme.b"], .systemAgent)
        XCTAssertEqual(byLabel["com.acme.c"], .systemDaemon)
    }
}
