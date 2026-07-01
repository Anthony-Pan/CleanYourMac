import Foundation

/// Read-only discovery of installed applications. Never modifies the filesystem.
/// Reads each bundle's `Contents/Info.plist` (binary or XML) to recover the
/// identity we later use to attribute leftover files.
public struct AppDiscovery {
    public let policy: UninstallPolicy

    public init(policy: UninstallPolicy = UninstallPolicy()) {
        self.policy = policy
    }

    /// Every `.app` found in the configured app roots that the policy would
    /// allow us to remove, sorted largest-first. Apple/system apps are included
    /// but flagged `isSystem` (the UI must refuse them).
    public func installedApps() -> [InstalledApp] {
        let fm = FileManager.default
        var seen = Set<String>()
        var apps: [InstalledApp] = []

        for root in policy.appRoots {
            let children = (try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            for child in children where child.pathExtension == "app" {
                // Skip duplicates reachable via more than one root / symlink.
                guard seen.insert(child.canonicalized.path).inserted else { continue }
                // SAFETY GATE: only surface bundles we could actually remove.
                guard policy.validateBundle(child) == nil else { continue }
                if let app = readApp(at: child) { apps.append(app) }
            }
        }

        return apps.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Parse a single `.app` bundle into an `InstalledApp`. Returns `nil` if the
    /// path is not a real application bundle directory.
    public func readApp(at url: URL) -> InstalledApp? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }

        let info = Self.infoDictionary(at: url)
        let bundleID = (info?["CFBundleIdentifier"] as? String)?.cleaned
        let displayName = (info?["CFBundleDisplayName"] as? String)?.cleaned
        let bundleName = (info?["CFBundleName"] as? String)?.cleaned
        let version = (info?["CFBundleShortVersionString"] as? String)?.cleaned
        let name = displayName ?? bundleName ?? url.deletingPathExtension().lastPathComponent

        return InstalledApp(
            url: url,
            name: name,
            bundleID: bundleID,
            version: version,
            sizeBytes: Scanner.allocatedSize(of: url),
            isSystem: Self.isSystemApp(bundleID: bundleID, url: url)
        )
    }

    // MARK: - Helpers

    /// Read `Contents/Info.plist`. `PropertyListSerialization` transparently
    /// handles both binary and XML property lists.
    static func infoDictionary(at appURL: URL) -> [String: Any]? {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        else { return nil }
        return obj as? [String: Any]
    }

    /// An app is "system" (never uninstallable) if its bundle ID is Apple's, or
    /// it resolves to somewhere under `/System` (defense in depth — we do not
    /// scan there, but a symlink could point in).
    static func isSystemApp(bundleID: String?, url: URL) -> Bool {
        if let id = bundleID?.lowercased(), id == "com.apple" || id.hasPrefix("com.apple.") {
            return true
        }
        let system = URL(fileURLWithPath: "/System").canonicalized
        return system.isSameOrAncestor(of: url.canonicalized)
    }
}

private extension String {
    /// Trimmed, or `nil` when empty after trimming.
    var cleaned: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
