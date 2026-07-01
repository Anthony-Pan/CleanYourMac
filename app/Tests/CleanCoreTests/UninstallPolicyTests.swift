import XCTest
@testable import CleanCore

/// Proves the uninstaller's gatekeeper refuses every dangerous path — for both
/// application bundles and leftover files — while still allowing the specific
/// items a real uninstall needs to remove.
final class UninstallPolicyTests: XCTestCase {
    var sandbox: URL!
    var apps: URL!
    var library: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cym-uninst-\(UUID().uuidString)")
        apps = sandbox.appendingPathComponent("Applications")
        library = sandbox.appendingPathComponent("Library")
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        for sub in ["Application Support", "Caches", "Preferences", "Containers"] {
            try fm.createDirectory(at: library.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: sandbox)
    }

    private func sandboxPolicy() -> UninstallPolicy {
        let leftoverRoots = ["Application Support", "Caches", "Preferences", "Containers"]
            .map { library.appendingPathComponent($0) }
        return UninstallPolicy(appRoots: [apps], leftoverRoots: leftoverRoots)
    }

    // MARK: - Bundles

    func test_acceptsBundleStrictlyInsideAppRoot() throws {
        let app = apps.appendingPathComponent("Foo.app")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        XCTAssertNil(sandboxPolicy().validateBundle(app))
    }

    func test_rejectsNonAppExtension() throws {
        let notAnApp = apps.appendingPathComponent("Foo.txt")
        try fm.createDirectory(at: notAnApp, withIntermediateDirectories: true)
        XCTAssertEqual(sandboxPolicy().validateBundle(notAnApp)?.reason, .outsideAllowedRoots)
    }

    func test_rejectsAppRootItself() {
        XCTAssertEqual(sandboxPolicy().validateBundle(apps)?.reason, .outsideAllowedRoots,
                       "the app root has no .app extension, so it is refused before anything else")
    }

    func test_rejectsBundleOutsideAppRoots() throws {
        let stray = library.appendingPathComponent("Rogue.app")
        try fm.createDirectory(at: stray, withIntermediateDirectories: true)
        XCTAssertEqual(sandboxPolicy().validateBundle(stray)?.reason, .outsideAllowedRoots)
    }

    func test_rejectsSymlinkedBundleThatEscapesAppRoot() throws {
        // A .app symlink inside the app root pointing OUT of it must be refused.
        let secret = sandbox.appendingPathComponent("Documents")
        try fm.createDirectory(at: secret, withIntermediateDirectories: true)
        let link = apps.appendingPathComponent("Escape.app")
        try fm.createSymbolicLink(at: link, withDestinationURL: secret)
        XCTAssertEqual(sandboxPolicy().validateBundle(link)?.reason, .outsideAllowedRoots)
    }

    // MARK: - Leftovers

    func test_acceptsLeftoverInsideRoot() throws {
        let item = library.appendingPathComponent("Caches/com.foo.Bar")
        try fm.createDirectory(at: item, withIntermediateDirectories: true)
        XCTAssertNil(sandboxPolicy().validateLeftover(item))
    }

    func test_rejectsLeftoverRootItself() {
        let root = library.appendingPathComponent("Caches")
        XCTAssertEqual(sandboxPolicy().validateLeftover(root)?.reason, .isAllowedRootItself,
                       "we remove named children, never the whole Caches directory")
    }

    func test_rejectsLeftoverOutsideRoots() throws {
        let outside = sandbox.appendingPathComponent("Documents/secret.txt")
        try fm.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: outside.path, contents: Data("keep".utf8)))
        XCTAssertEqual(sandboxPolicy().validateLeftover(outside)?.reason, .outsideAllowedRoots)
    }

    func test_rejectsLeftoverSymlinkThatEscapesRoot() throws {
        let secret = sandbox.appendingPathComponent("Secret")
        try fm.createDirectory(at: secret, withIntermediateDirectories: true)
        let link = library.appendingPathComponent("Caches/escape")
        try fm.createSymbolicLink(at: link, withDestinationURL: secret)
        XCTAssertEqual(sandboxPolicy().validateLeftover(link)?.reason, .outsideAllowedRoots)
    }

    // MARK: - Real (production) default policy

    func test_defaultPolicyAllowsRealAppBundleButRefusesTheApplicationsRoot() {
        let policy = UninstallPolicy()
        // A specific app inside /Applications is removable (depth 3 is allowed
        // for bundles); the /Applications directory itself never is.
        XCTAssertNil(policy.validateBundle(URL(fileURLWithPath: "/Applications/Foo.app")))
        XCTAssertEqual(policy.validateBundle(URL(fileURLWithPath: "/Applications"))?.reason, .outsideAllowedRoots)
        // A .app too shallow to be inside any app root is refused on depth.
        XCTAssertEqual(policy.validateBundle(URL(fileURLWithPath: "/x.app"))?.reason, .tooShallow)
        // The filesystem root has no .app extension → refused immediately.
        XCTAssertNotNil(policy.validateBundle(URL(fileURLWithPath: "/")))
    }

    func test_defaultPolicyRefusesSystemApplications() {
        let policy = UninstallPolicy()
        XCTAssertEqual(
            policy.validateBundle(URL(fileURLWithPath: "/System/Applications/Calculator.app"))?.reason,
            .outsideAllowedRoots,
            "apps on the sealed system volume are never inside an app root")
    }

    func test_defaultPolicyProtectsLibraryRootsButAllowsNamedChildren() {
        let policy = UninstallPolicy()
        let home = fm.homeDirectoryForCurrentUser
        // Named children under Library subdirectories are removable…
        XCTAssertNil(policy.validateLeftover(home.appendingPathComponent("Library/Caches/com.test.demo")))
        XCTAssertNil(policy.validateLeftover(home.appendingPathComponent("Library/Application Support/com.test.demo")))
        // …but never the roots themselves, and never ~/Library as a whole.
        XCTAssertEqual(policy.validateLeftover(home.appendingPathComponent("Library/Caches"))?.reason, .isAllowedRootItself)
        XCTAssertEqual(policy.validateLeftover(home.appendingPathComponent("Library"))?.reason, .protectedPath)
        XCTAssertEqual(policy.validateLeftover(home.appendingPathComponent("Library/Application Support"))?.reason, .protectedPath)
    }
}
