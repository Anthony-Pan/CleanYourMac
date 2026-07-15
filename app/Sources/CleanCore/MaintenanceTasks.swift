import Foundation

// MARK: - Maintenance task (declarative)

/// One fixed, no-sudo macOS maintenance action.
///
/// Tasks are *declarative* on purpose, mirroring `CleanupTarget`: the set of
/// commands the app ever runs is a fixed, reviewable list. Executable paths
/// are absolute and arguments are hard-coded literals — there is no shell, no
/// string interpolation, and no code path that runs a command not described
/// by one of these entries.
public struct MaintenanceTask: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let detail: String
    /// Absolute path to the tool. Launched via `Process.executableURL`, never
    /// through a shell.
    public let executablePath: String
    /// Fixed argument list — literals only, decided at compile time.
    public let arguments: [String]
    /// User-visible side effect worth calling out before running (e.g. an app
    /// restart). `nil` when the task is invisible to the user.
    public let warning: String?

    public init(
        id: String,
        name: String,
        detail: String,
        executablePath: String,
        arguments: [String],
        warning: String? = nil
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.executablePath = executablePath
        self.arguments = arguments
        self.warning = warning
    }
}

// MARK: - Registry

public extension MaintenanceTask {
    /// The complete fixed set of maintenance tasks, in run order. Every task is
    /// safe without sudo and touches no user files.
    static let registry: [MaintenanceTask] = [
        MaintenanceTask(
            id: "flush-dns",
            name: "Flush DNS Cache",
            detail: "Clears cached DNS lookups that can go stale after network changes.",
            executablePath: "/usr/bin/dscacheutil",
            arguments: ["-flushcache"]
        ),
        MaintenanceTask(
            id: "rebuild-launchservices",
            name: "Rebuild Launch Services",
            detail: "Rebuilds the database behind 'Open With' menus; fixes duplicate entries. Can take a minute.",
            executablePath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            arguments: ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"]
        ),
        MaintenanceTask(
            id: "reset-quicklook",
            name: "Reset Quick Look",
            detail: "Resets the thumbnail cache so previews regenerate.",
            executablePath: "/usr/bin/qlmanage",
            arguments: ["-r", "cache"]
        ),
        MaintenanceTask(
            id: "restart-finder",
            name: "Restart Finder",
            detail: "Relaunches Finder to clear glitches with windows, icons and the desktop.",
            executablePath: "/usr/bin/killall",
            arguments: ["Finder"],
            warning: "Finder will close and reopen its windows."
        ),
        MaintenanceTask(
            id: "restart-dock",
            name: "Restart Dock",
            detail: "Relaunches the Dock to fix frozen icons and Mission Control hiccups.",
            executablePath: "/usr/bin/killall",
            arguments: ["Dock"],
            warning: "The Dock will briefly disappear."
        ),
    ]
}
