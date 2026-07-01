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

let args = Set(CommandLine.arguments.dropFirst())
let doClean = args.contains("--clean")
let dryRun = args.contains("--dry-run")

let categories = CleanupCategory.mvpUserSafe
let policy = SafetyPolicy.policy(for: categories)
let scanner = Scanner(policy: policy)

print("🧹 CleanYourMac — Smart Scan\n")

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
