// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FeatherSweep",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CleanerCore", targets: ["CleanerCore"]), .executable(name: "FeatherSweep", targets: ["FeatherSweep"])],
    targets: [
        .target(name: "CleanerCore"),
        .executableTarget(name: "FeatherSweep", dependencies: ["CleanerCore"]),
        .testTarget(name: "CleanerCoreTests", dependencies: ["CleanerCore"]),
        .testTarget(name: "FeatherSweepTests", dependencies: ["FeatherSweep", "CleanerCore"])
    ]
)
