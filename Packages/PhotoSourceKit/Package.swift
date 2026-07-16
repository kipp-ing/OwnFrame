// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotoSourceKit",
    platforms: [
        // iPadOS target for the app; macOS enables `swift test` on the host without a simulator.
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PhotoSourceKit", targets: ["PhotoSourceKit"]),
        .library(name: "PhotoSourceTestSupport", targets: ["PhotoSourceTestSupport"]),
    ],
    targets: [
        .target(name: "PhotoSourceKit"),
        .target(
            name: "PhotoSourceTestSupport",
            dependencies: ["PhotoSourceKit"]
        ),
        .testTarget(
            name: "PhotoSourceKitTests",
            dependencies: ["PhotoSourceKit", "PhotoSourceTestSupport"]
        ),
    ]
)
