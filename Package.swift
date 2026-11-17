// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Recall",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "RecallCore"),
        .executableTarget(name: "Recall", dependencies: ["RecallCore"]),
        .testTarget(name: "RecallCoreTests", dependencies: ["RecallCore"]),
    ]
)
