// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FeatherSweep",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CleanerCore", targets: ["CleanerCore"]), .executable(name: "FeatherSweep", targets: ["FeatherSweep"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .target(name: "CleanerCore"),
        .executableTarget(name: "FeatherSweep", dependencies: ["CleanerCore", .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "CleanerCoreTests", dependencies: ["CleanerCore"]),
        .testTarget(name: "FeatherSweepTests", dependencies: ["FeatherSweep", "CleanerCore"])
    ]
)
