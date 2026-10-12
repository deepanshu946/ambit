// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FlowCore",
    platforms: [.macOS(.v26)],
    products: [.library(name: "FlowCore", targets: ["FlowCore"])],
    targets: [
        .target(name: "FlowCore"),
        .testTarget(name: "FlowCoreTests", dependencies: ["FlowCore"]),
    ]
)
