import XCTest
@testable import CleanCore

/// End-to-end tests for app discovery, leftover attribution, and the safety
/// invariants of the uninstall executor — all inside a temp sandbox so they
/// never touch the real disk or Trash.
final class AppUninstallerTests: XCTestCase {
    var sandbox: URL!
    var apps: URL!
    var library: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cym-app-\(UUID().uuidString)")
        apps = sandbox.appendingPathComponent("Applications")
        library = sandbox.appendingPathComponent("Library")
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: sandbox)
    }

    // MARK: - Fixtures

    private func policy() -> UninstallPolicy {
        UninstallPolicy(appRoots: [apps], leftoverRoots: UninstallPolicy.leftoverRoots(under: library))
    }

    private func uninstaller(_ disposer: FileDisposer = RecordingDisposer()) -> AppUninstaller {
        AppUninstaller(policy: policy(), disposer: disposer, libraryURL: library)
    }

    private func writeInfoPlist(at contents: URL, bundleID: String?, name: String?, version: String?) throws {
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        var dict = ""
        if let name { dict += "<key>CFBundleName</key><string>\(name)</string>" }
        if let version { dict += "<key>CFBundleShortVersionString</key><string>\(version)</string>" }
        if let bundleID { dict += "<key>CFBundleIdentifier</key><string>\(bundleID)</string>" }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>\(dict)</dict></plist>
        """
        try plist.write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
    }

    @discardableResult
    private func makeApp(fileName: String, bundleID: String?, name: String, version: String = "1.0", embeds: [String] = []) throws -> URL {
        let app = apps.appendingPathComponent(fileName)
        let contents = app.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        // A non-empty executable so the bundle has a real size.
        XCTAssertTrue(fm.createFile(
            atPath: contents.appendingPathComponent("MacOS/exe").path,
            contents: Data(repeating: 0x41, count: 4_096)))
        try writeInfoPlist(at: contents, bundleID: bundleID, name: name, version: version)

        // Embedded app extensions (Contents/PlugIns/<id>.appex).
        for id in embeds {
            let appex = contents.appendingPathComponent("PlugIns/\(id).appex/Contents")
            try writeInfoPlist(at: appex, bundleID: id, name: nil, version: version)
        }
        return app
    }

    private func makeDir(_ relative: String) throws -> URL {
        let url = library.appendingPathComponent(relative)
        try fm.createDirectory(at: url.appendingPathComponent("payload"), withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: url.appendingPathComponent("payload/f").path,
                                    contents: Data(repeating: 0x42, count: 1_024)))
        return url
    }

    @discardableResult
    private func makeFile(_ relative: String) throws -> URL {
        let url = library.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: url.path, contents: Data(repeating: 0x43, count: 512)))
        return url
    }

    /// Foo.app (com.foo.Bar) plus a realistic spread of leftovers and decoys.
    /// Foo embeds a genuine `com.foo.Bar.ShareExtension` app extension.
    private func installFooWithLeftovers() throws -> InstalledApp {
        let bundle = try makeApp(fileName: "Foo.app", bundleID: "com.foo.Bar", name: "Foo",
                                 embeds: ["com.foo.Bar.ShareExtension"])

        // High-confidence (bundle-ID) leftovers.
        try makeDir("Application Support/com.foo.Bar")
        try makeDir("Caches/com.foo.Bar")
        try makeFile("Preferences/com.foo.Bar.plist")
        try makeFile("Preferences/ByHost/com.foo.Bar.ABCDEF.plist")
        try makeDir("Containers/com.foo.Bar.ShareExtension")   // dot-boundary child
        try makeDir("Saved Application State/com.foo.Bar.savedState")
        try makeDir("HTTPStorages/com.foo.Bar")
        try makeFile("Cookies/com.foo.Bar.binarycookies")
        try makeDir("Application Scripts/com.foo.Bar")
        try makeFile("LaunchAgents/com.foo.Bar.plist")

        // Medium-confidence (heuristic) leftovers.
        try makeDir("Application Support/Foo")                 // app-name match
        try makeDir("Group Containers/A1B2C3D4E5.com.foo.Bar") // team-prefixed

        // Decoys that must NOT match.
        try makeDir("Application Support/com.other.App")
        try makeFile("Preferences/com.foo.Barometer.plist")   // prefix-bleed guard
        try makeDir("Caches/UnrelatedThing")

        return AppDiscovery(policy: policy()).readApp(at: bundle)!
    }

    // MARK: - Discovery

    func test_discoveryReadsBundleIdentityAndSize() throws {
        try makeApp(fileName: "Foo.app", bundleID: "com.foo.Bar", name: "Foo", version: "3.2")
        let found = AppDiscovery(policy: policy()).installedApps()
        let foo = try XCTUnwrap(found.first { $0.name == "Foo" })
        XCTAssertEqual(foo.bundleID, "com.foo.Bar")
        XCTAssertEqual(foo.version, "3.2")
        XCTAssertFalse(foo.isSystem)
        XCTAssertGreaterThan(foo.sizeBytes, 0)
    }

    func test_discoveryFlagsAppleAppsAsSystem() throws {
        let bundle = try makeApp(fileName: "SystemThing.app", bundleID: "com.apple.SomeTool", name: "SystemThing")
        let app = try XCTUnwrap(AppDiscovery(policy: policy()).readApp(at: bundle))
        XCTAssertTrue(app.isSystem)
    }

    // MARK: - Leftover attribution

    func test_planMatchesBundleIDLeftoversAndBundleItself() throws {
        let foo = try installFooWithLeftovers()
        let plan = uninstaller().plan(for: foo)
        let names = Set(plan.leftovers.map { $0.url.lastPathComponent })

        XCTAssertTrue(names.contains("Foo.app"), "the bundle itself is part of the plan")
        for expected in [
            "com.foo.Bar",                       // Application Support / Caches / Containers-family
            "com.foo.Bar.plist",                 // Preferences
            "com.foo.Bar.ABCDEF.plist",          // ByHost
            "com.foo.Bar.ShareExtension",        // dot-boundary container
            "com.foo.Bar.savedState",
            "com.foo.Bar.binarycookies",
        ] {
            XCTAssertTrue(names.contains(expected), "expected to match \(expected)")
        }
    }

    func test_planExcludesDecoys() throws {
        let foo = try installFooWithLeftovers()
        let plan = uninstaller().plan(for: foo)
        let paths = plan.leftovers.map { $0.url.path }

        XCTAssertFalse(paths.contains { $0.hasSuffix("com.other.App") },
                       "an unrelated app's folder must never match")
        XCTAssertFalse(paths.contains { $0.hasSuffix("com.foo.Barometer.plist") },
                       "prefix-bleed (com.foo.Bar vs com.foo.Barometer) must be rejected")
        XCTAssertFalse(paths.contains { $0.hasSuffix("UnrelatedThing") })
    }

    func test_embeddedExtensionContainerIsHighConfidence() throws {
        let foo = try installFooWithLeftovers()
        let plan = uninstaller().plan(for: foo)
        let ext = plan.leftovers.first { $0.url.lastPathComponent == "com.foo.Bar.ShareExtension" }
        XCTAssertEqual(ext?.confidence, .high,
                       "a container for a genuinely embedded app extension is high confidence")
    }

    func test_dottedSiblingAppDataIsNeverAttributed() throws {
        // The critical case: uninstalling com.foo.Bar must NOT sweep up a
        // separately-installed com.foo.Bar.Editor (a real app, not an extension).
        try makeApp(fileName: "Foo.app", bundleID: "com.foo.Bar", name: "Foo")
        try makeApp(fileName: "FooEditor.app", bundleID: "com.foo.Bar.Editor", name: "FooEditor")
        // The Editor's own sandbox container + preferences live under Foo's namespace.
        try makeDir("Containers/com.foo.Bar.Editor")
        try makeFile("Preferences/com.foo.Bar.Editor.plist")
        try makeDir("WebKit/com.foo.Bar.Editor")
        // Foo's own container, which SHOULD match.
        try makeDir("Containers/com.foo.Bar")

        let foo = AppDiscovery(policy: policy()).readApp(at: apps.appendingPathComponent("Foo.app"))!
        let others: Set<String> = ["com.foo.Bar.Editor"]
        let plan = uninstaller().plan(for: foo, otherAppIDs: others)
        let paths = plan.leftovers.map { $0.url.path }

        XCTAssertTrue(paths.contains { $0.hasSuffix("Containers/com.foo.Bar") },
                      "Foo's own container is still attributed")
        for sibling in ["Containers/com.foo.Bar.Editor", "Preferences/com.foo.Bar.Editor.plist", "WebKit/com.foo.Bar.Editor"] {
            XCTAssertFalse(paths.contains { $0.hasSuffix(sibling) },
                           "a separately-installed sibling app's data (\(sibling)) must never be attributed to Foo")
        }
    }

    func test_unknownDottedChildIsMediumNotAutoSelected() throws {
        // A dotted-namespace file that is neither an embedded extension nor a
        // known installed app is offered for review (medium), never auto-selected.
        try makeApp(fileName: "Foo.app", bundleID: "com.foo.Bar", name: "Foo")
        try makeDir("Containers/com.foo.Bar.Mystery")

        let foo = AppDiscovery(policy: policy()).readApp(at: apps.appendingPathComponent("Foo.app"))!
        let plan = uninstaller().plan(for: foo)
        let mystery = plan.leftovers.first { $0.url.lastPathComponent == "com.foo.Bar.Mystery" }
        XCTAssertEqual(mystery?.confidence, .medium,
                       "an unconfirmed dotted-namespace neighbour is medium (opt-in), not high")
    }

    func test_nameAndGroupMatchesAreMediumConfidence() throws {
        let foo = try installFooWithLeftovers()
        let plan = uninstaller().plan(for: foo)

        let mediums = plan.leftovers.filter { $0.confidence == .medium }.map { $0.url.lastPathComponent }
        XCTAssertTrue(mediums.contains("Foo"), "the app-name folder is heuristic → medium")
        XCTAssertTrue(mediums.contains("A1B2C3D4E5.com.foo.Bar"), "group containers are shared → medium")

        // The bundle-ID Application Support folder is high confidence.
        let appSupportHigh = plan.leftovers.contains {
            $0.kind == .applicationSupport && $0.url.lastPathComponent == "com.foo.Bar" && $0.confidence == .high
        }
        XCTAssertTrue(appSupportHigh)
    }

    // MARK: - Execution safety

    func test_dryRunTouchesNothing() throws {
        let foo = try installFooWithLeftovers()
        let disposer = RecordingDisposer()
        let report = AppUninstaller(policy: policy(), disposer: disposer, libraryURL: library)
            .uninstall(uninstaller().plan(for: foo), dryRun: true)

        XCTAssertTrue(disposer.disposed.isEmpty)
        XCTAssertGreaterThan(report.freedBytes, 0)
        XCTAssertTrue(fm.fileExists(atPath: foo.url.path), "the app bundle must still exist after a dry run")
    }

    func test_realUninstallRemovesOnlySelectedItems() throws {
        let foo = try installFooWithLeftovers()
        let disposer = RecordingDisposer()
        let engine = AppUninstaller(policy: policy(), disposer: disposer, libraryURL: library)
        let plan = engine.plan(for: foo)

        // Select only the high-confidence items (the default the UI would use).
        let highIDs = Set(plan.leftovers.filter { $0.confidence == .high }.map(\.id))
        let report = engine.uninstall(plan, selecting: highIDs, dryRun: false)

        XCTAssertEqual(disposer.disposed.count, highIDs.count)
        XCTAssertEqual(report.trashed.count, highIDs.count)
        XCTAssertTrue(report.failed.isEmpty)
        XCTAssertTrue(report.blocked.isEmpty)

        // High-confidence items are gone; the medium ones were not selected.
        XCTAssertFalse(fm.fileExists(atPath: foo.url.path))
        XCTAssertTrue(fm.fileExists(atPath: library.appendingPathComponent("Application Support/Foo").path),
                      "an unselected medium-confidence item must survive")
    }

    func test_executorRefusesLeftoverOutsideRoots() throws {
        // A hand-crafted plan whose "leftover" points at a real document must be
        // refused by the re-validation gate.
        let important = sandbox.appendingPathComponent("Documents/important.txt")
        try fm.createDirectory(at: important.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: important.path, contents: Data("keep".utf8)))

        let app = InstalledApp(url: apps.appendingPathComponent("X.app"), name: "X",
                               bundleID: "com.x.Y", version: nil, sizeBytes: 0, isSystem: false)
        let bogus = AppLeftover(url: important, kind: .applicationSupport, confidence: .high, sizeBytes: 4)
        let plan = UninstallPlan(app: app, leftovers: [bogus])

        let disposer = RecordingDisposer()
        let report = AppUninstaller(policy: policy(), disposer: disposer, libraryURL: library)
            .uninstall(plan, dryRun: false)

        XCTAssertTrue(disposer.disposed.isEmpty)
        XCTAssertEqual(report.blocked.count, 1)
        XCTAssertEqual(report.blocked.first?.reason, .outsideAllowedRoots)
        XCTAssertTrue(fm.fileExists(atPath: important.path), "the important file must survive")
    }

    func test_systemAppYieldsEmptyPlanAndBundleIsNeverRemoved() throws {
        let bundle = try makeApp(fileName: "SystemThing.app", bundleID: "com.apple.SomeTool", name: "SystemThing")
        let app = try XCTUnwrap(AppDiscovery(policy: policy()).readApp(at: bundle))

        // Planning refuses system apps outright.
        XCTAssertTrue(uninstaller().plan(for: app).leftovers.isEmpty)

        // Even a crafted plan that tries to trash a system bundle is blocked.
        let crafted = UninstallPlan(app: app, leftovers: [
            AppLeftover(url: bundle, kind: .bundle, confidence: .high, sizeBytes: app.sizeBytes),
        ])
        let disposer = RecordingDisposer()
        let report = AppUninstaller(policy: policy(), disposer: disposer, libraryURL: library)
            .uninstall(crafted, dryRun: false)

        XCTAssertTrue(disposer.disposed.isEmpty)
        XCTAssertEqual(report.blocked.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: bundle.path), "a system app bundle must never be removed")
    }
}
