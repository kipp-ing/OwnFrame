// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ConfigSyncKit",
    platforms: [
        .iOS(.v17),
        .tvOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ConfigSyncKit", targets: ["ConfigSyncKit"]),
    ],
    targets: [
        .target(name: "ConfigSyncKit"),
        .testTarget(name: "ConfigSyncKitTests", dependencies: ["ConfigSyncKit"]),
    ]
)
