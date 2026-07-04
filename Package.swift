// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SnapCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SnapCore", targets: ["SnapCore"]),
    ],
    targets: [
        .target(name: "SnapCore"),
        .executableTarget(name: "snapverify", dependencies: ["SnapCore"]),
    ]
)
