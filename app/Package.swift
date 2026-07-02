// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CleanYourMac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CleanCore", targets: ["CleanCore"]),
        .library(name: "CleanUI", targets: ["CleanUI"]),
        .executable(name: "smartclean", targets: ["smartclean"]),
        .executable(name: "CleanYourMacApp", targets: ["CleanYourMacApp"]),
        .executable(name: "snapshot", targets: ["snapshot"]),
    ],
    targets: [
        .target(name: "CleanCore"),
        .target(
            name: "CleanUI",
            dependencies: ["CleanCore"],
            resources: [.copy("Resources/IconArt.png")]
        ),
        .executableTarget(name: "smartclean", dependencies: ["CleanCore"]),
        .executableTarget(name: "CleanYourMacApp", dependencies: ["CleanUI"]),
        .executableTarget(name: "snapshot", dependencies: ["CleanUI"]),
        .testTarget(name: "CleanCoreTests", dependencies: ["CleanCore"]),
    ],
    // Use the Swift 5 language mode for now to avoid strict-concurrency friction
    // while the codebase is small. We can tighten to Swift 6 mode later.
    swiftLanguageModes: [.v5]
)
