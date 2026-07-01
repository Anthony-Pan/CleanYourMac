import Foundation

public extension CleanupCategory {
    /// MVP category set: only user-owned, no-root, safely-reclaimable locations.
    /// Every item here is regenerated automatically by the system or a tool, so
    /// trashing it is safe. Deliberately excludes Documents/Desktop/Downloads,
    /// system directories, and anything requiring `sudo`.
    static var mvpUserSafe: [CleanupCategory] {
        [
            CleanupCategory(
                id: "user-caches",
                nameEN: "User Caches",
                nameCN: "用户缓存",
                detailEN: "App caches that are rebuilt automatically.",
                detailCN: "应用缓存,系统会自动重建。",
                targets: [CleanupTarget(path: "~/Library/Caches")]
            ),
            CleanupCategory(
                id: "app-logs",
                nameEN: "Application Logs",
                nameCN: "应用日志",
                detailEN: "Diagnostic logs written by apps.",
                detailCN: "应用写入的诊断日志。",
                targets: [CleanupTarget(path: "~/Library/Logs")]
            ),
            CleanupCategory(
                id: "xcode-derived-data",
                nameEN: "Xcode Derived Data",
                nameCN: "Xcode 派生数据",
                detailEN: "Build intermediates Xcode regenerates on next build.",
                detailCN: "Xcode 的编译中间产物,下次构建会重新生成。",
                targets: [CleanupTarget(path: "~/Library/Developer/Xcode/DerivedData")]
            ),
            CleanupCategory(
                id: "dev-tool-caches",
                nameEN: "Developer Tool Caches",
                nameCN: "开发者工具缓存",
                detailEN: "npm / Gradle / CocoaPods download caches.",
                detailCN: "npm / Gradle / CocoaPods 的下载缓存。",
                targets: [
                    CleanupTarget(path: "~/.npm/_cacache"),
                    CleanupTarget(path: "~/.gradle/caches"),
                    CleanupTarget(path: "~/Library/Caches/CocoaPods"),
                ]
            ),
        ]
    }
}

public extension SafetyPolicy {
    /// Build a policy whose allowlist is exactly the roots named by these
    /// categories — the scanner/cleaner can never touch anything else.
    static func policy(for categories: [CleanupCategory]) -> SafetyPolicy {
        let roots = categories
            .flatMap { $0.targets }
            .map { Scanner.expand($0.path) }
        return SafetyPolicy(allowedRoots: roots)
    }
}
