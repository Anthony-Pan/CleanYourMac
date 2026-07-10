import XCTest
@testable import CleanCore

/// Proves the gatekeeper refuses every dangerous path we can think of.
final class SafetyPolicyTests: XCTestCase {
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

    private func policy() -> SafetyPolicy {
        SafetyPolicy(allowedRoots: [caches])   // uses default protected paths
    }

    func test_acceptsItemStrictlyInsideAllowedRoot() throws {
        let item = caches.appendingPathComponent("SomeApp")
        try fm.createDirectory(at: item, withIntermediateDirectories: true)
        XCTAssertNil(policy().validate(item), "an item inside the cleanable root must be allowed")
    }

    func test_rejectsTheAllowedRootItself() {
        // We clean *contents*, never the root directory.
        XCTAssertEqual(policy().validate(caches)?.reason, .isAllowedRootItself)
    }

    func test_rejectsFilesystemRootAndShallowPaths() {
        XCTAssertEqual(policy().validate(URL(fileURLWithPath: "/"))?.reason, .tooShallow)
        XCTAssertEqual(policy().validate(URL(fileURLWithPath: "/Users"))?.reason, .tooShallow)
        XCTAssertEqual(policy().validate(URL(fileURLWithPath: "/Users/somebody"))?.reason, .tooShallow)
    }

    func test_rejectsPathsOutsideAllowedRoots() throws {
        let outside = sandbox.appendingPathComponent("Documents/secret.txt")
        try fm.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: outside.path, contents: Data("keep".utf8)))
        XCTAssertEqual(policy().validate(outside)?.reason, .outsideAllowedRoots)
    }

    func test_rejectsSymlinkThatEscapesTheAllowedRoot() throws {
        // A symlink that lives *inside* Caches but points *outside* must be refused.
        let secret = sandbox.appendingPathComponent("Secret")
        try fm.createDirectory(at: secret, withIntermediateDirectories: true)
        let link = caches.appendingPathComponent("escape")
        try fm.createSymbolicLink(at: link, withDestinationURL: secret)
        XCTAssertEqual(policy().validate(link)?.reason, .outsideAllowedRoots)
    }

    func test_rejectsProtectedPathAndItsAncestors() throws {
        let keep = caches.appendingPathComponent("keep")
        try fm.createDirectory(at: keep, withIntermediateDirectories: true)
        let deeper = keep.appendingPathComponent("child")
        let p = SafetyPolicy(allowedRoots: [caches], protectedPaths: [keep])
        XCTAssertEqual(p.validate(keep)?.reason, .protectedPath, "the protected path itself is refused")
        XCTAssertNil(p.validate(deeper), "a descendant of a protected path is still cleanable")
    }

    func test_defaultProtectedPathsCoverHomeAndSystemRoots() {
        let home = fm.homeDirectoryForCurrentUser
        // Deleting the real home or its top-level personal folders must never be allowed,
        // even if they were (mistakenly) declared as an allowed root.
        let reckless = SafetyPolicy(allowedRoots: [home])
        XCTAssertNotNil(reckless.validate(home.appendingPathComponent("Documents")),
                        "~/Documents must be refused")
        XCTAssertNotNil(reckless.validate(home.appendingPathComponent("Desktop")),
                        "~/Desktop must be refused")
    }

    // MARK: - Exact targets

    func test_exactTargetPassesOutsideAnyRoot() throws {
        // A declared exact target passes even though no allowed root contains it.
        let db = sandbox.appendingPathComponent("Preferences/quarantine.db")
        try fm.createDirectory(at: db.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: db.path, contents: Data("x".utf8)))

        let p = SafetyPolicy(allowedRoots: [caches], allowedExactTargets: [db])
        XCTAssertNil(p.validate(db), "a declared exact target must pass")
    }

    func test_nonListedSiblingOfExactTargetFails() throws {
        // The sibling right next to an exact target gets no free pass.
        let dir = sandbox.appendingPathComponent("Preferences")
        let db = dir.appendingPathComponent("quarantine.db")
        let sibling = dir.appendingPathComponent("settings.plist")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: sibling.path, contents: Data("keep".utf8)))

        let p = SafetyPolicy(allowedRoots: [caches], allowedExactTargets: [db])
        XCTAssertEqual(p.validate(sibling)?.reason, .outsideAllowedRoots,
                       "a non-listed sibling of an exact target must be refused")
    }

    func test_exactTargetStillSubjectToMinimumDepth() {
        // Depth is checked before the exact-target match — a shallow path can
        // never be sanctioned, even if explicitly listed.
        let shallow = URL(fileURLWithPath: "/Users/somebody")
        let p = SafetyPolicy(allowedRoots: [], allowedExactTargets: [shallow])
        XCTAssertEqual(p.validate(shallow)?.reason, .tooShallow)
    }

    func test_exactTargetStillSubjectToProtectedPaths() throws {
        // Protected paths are checked before the exact-target match — listing a
        // protected location as an exact target must not unlock it.
        let keep = sandbox.appendingPathComponent("Keep")
        try fm.createDirectory(at: keep, withIntermediateDirectories: true)
        let p = SafetyPolicy(allowedRoots: [], allowedExactTargets: [keep], protectedPaths: [keep])
        XCTAssertEqual(p.validate(keep)?.reason, .protectedPath)
    }

    func test_exactTargetDirPassesButChildrenDoNot() throws {
        // An exact-target directory matches by full-path equality only — its
        // children fail unless they live under a declared root.
        let sessions = sandbox.appendingPathComponent("zsh_sessions")
        let child = sessions.appendingPathComponent("session1.hist")
        try fm.createDirectory(at: sessions, withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: child.path, contents: Data("cmd".utf8)))

        let p = SafetyPolicy(allowedRoots: [caches], allowedExactTargets: [sessions])
        XCTAssertNil(p.validate(sessions), "the exact-target directory itself must pass")
        XCTAssertEqual(p.validate(child)?.reason, .outsideAllowedRoots,
                       "children of an exact target get no free pass")
    }
}
