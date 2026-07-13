import CleanCore
import Foundation

// A tiny command-line front end for the CleanCore engine.
//
// Default: SCAN ONLY (read-only). Prints reclaimable space per category.
//   swift run smartclean
// Preview what a clean would do, still touching nothing:
//   swift run smartclean --dry-run
// Actually clean (moves items to Trash — reversible from Finder):
//   swift run smartclean --clean

let rawArgs = Array(CommandLine.arguments.dropFirst())

// `apps` subcommand: read-only application uninstaller preview.
//   swift run smartclean apps            -> list installed (non-system) apps
//   swift run smartclean apps <query>    -> preview the removal plan for a match
if rawArgs.first == "apps" {
    runAppsCommand(query: rawArgs.dropFirst().first)
    exit(0)
}

let args = Set(rawArgs)
let doClean = args.contains("--clean")
let dryRun = args.contains("--dry-run")

let categories = CleanupCategory.mvpUserSafe
let policy = SafetyPolicy.policy(for: categories)
let scanner = Scanner(policy: policy)

print("🧹 CleanYourMac — System Junk scan\n")

let groups = scanner.scan(categories: categories)
var total: Int64 = 0
for group in groups {
    let size = ByteFormat.human(group.totalBytes)
    print("  \(group.category.nameEN.padding(toLength: 26, withPad: " ", startingAt: 0)) \(size)  (\(group.items.count) items)")
    total += group.totalBytes
}
print("\n  Total reclaimable: \(ByteFormat.human(total))\n")

let allItems = groups.flatMap { $0.items }

if doClean {
    print("Moving \(allItems.count) items to the Trash (reversible)…")
    let cleaner = Cleaner(policy: policy)
    let report = cleaner.clean(allItems, dryRun: false)
    print("  Trashed: \(report.trashed.count)")
    print("  Freed:   \(ByteFormat.human(report.freedBytes))")
    if !report.blocked.isEmpty { print("  Blocked by safety: \(report.blocked.count)") }
    if !report.failed.isEmpty { print("  Failed:  \(report.failed.count)") }
} else if dryRun {
    let cleaner = Cleaner(policy: policy)
    let report = cleaner.clean(allItems, dryRun: true)
    print("DRY RUN — nothing was deleted. Would trash \(report.trashed.count) items, freeing \(ByteFormat.human(report.freedBytes)).")
} else {
    print("Scan only. Run with --dry-run to preview, or --clean to move to Trash.")
}

// MARK: - `apps` subcommand (read-only)

func runAppsCommand(query: String?) {
    let discovery = AppDiscovery()
    let uninstaller = AppUninstaller()
    let apps = discovery.installedApps()

    guard let query else {
        print("📦 Installed apps (\(apps.filter { !$0.isSystem }.count) removable)\n")
        for app in apps where !app.isSystem {
            let id = app.bundleID ?? "—"
            print("  \(app.name.padding(toLength: 28, withPad: " ", startingAt: 0)) \(ByteFormat.human(app.sizeBytes).padding(toLength: 10, withPad: " ", startingAt: 0)) \(id)")
        }
        print("\nPreview an uninstall (read-only): swift run smartclean apps <name>")
        return
    }

    let q = query.lowercased()
    guard let app = apps.first(where: { $0.name.lowercased().contains(q) || ($0.bundleID?.lowercased().contains(q) ?? false) }) else {
        print("No app matches “\(query)”.")
        return
    }

    print("🧯 Uninstall preview — \(app.name)  \(app.bundleID ?? "")\n")
    guard !app.isSystem else {
        print("  This is a system app and is protected — it can’t be uninstalled.")
        return
    }

    let otherIDs = Set(apps.compactMap { $0.bundleID }).subtracting([app.bundleID].compactMap { $0 })
    let plan = uninstaller.plan(for: app, otherAppIDs: otherIDs)
    for leftover in plan.leftovers {
        let mark = leftover.confidence == .high ? "✓" : "?"
        let kind = leftover.kind.titleEN.padding(toLength: 22, withPad: " ", startingAt: 0)
        let size = ByteFormat.human(leftover.sizeBytes).padding(toLength: 10, withPad: " ", startingAt: 0)
        print("  \(mark) \(kind) \(size) \(leftover.url.path)")
    }
    print("\n  Total: \(ByteFormat.human(plan.totalBytes)) across \(plan.leftovers.count) items")
    print("  ✓ = matched by bundle id (safe)   ? = heuristic match (review)")
    print("  (Preview only — nothing was touched. Uninstall from the app to move to Trash.)")
}
