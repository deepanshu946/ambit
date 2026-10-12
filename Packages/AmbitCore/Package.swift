// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AmbitCore",
    platforms: [.macOS(.v26)],
    products: [.library(name: "AmbitCore", targets: ["AmbitCore"])],
    targets: [
        .target(name: "AmbitCore"),
        .testTarget(name: "AmbitCoreTests", dependencies: ["AmbitCore"]),
    ]
)
