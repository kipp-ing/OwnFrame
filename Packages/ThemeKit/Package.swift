// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThemeKit",
    platforms: [
        // iPadOS target for the app; macOS enables `swift test` on the host without a simulator.
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ThemeKit", targets: ["ThemeKit"]),
        .library(name: "ThemeKitTestSupport", targets: ["ThemeKitTestSupport"]),
    ],
    targets: [
        .target(name: "ThemeKit"),
        .target(
            name: "ThemeKitTestSupport",
            dependencies: ["ThemeKit"]
        ),
        .testTarget(
            name: "ThemeKitTests",
            dependencies: ["ThemeKit", "ThemeKitTestSupport"]
        ),
    ]
)
