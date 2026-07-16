// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotoLibraryKit",
    platforms: [
        // iPadOS target for the app; macOS enables `swift test` on the host without a simulator
        // (all logic sits behind PhotoLibraryGateway — only PHKitGateway touches PhotoKit).
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PhotoLibraryKit", targets: ["PhotoLibraryKit"]),
    ],
    dependencies: [
        .package(path: "../PhotoSourceKit"),
    ],
    targets: [
        .target(
            name: "PhotoLibraryKit",
            dependencies: [
                .product(name: "PhotoSourceKit", package: "PhotoSourceKit"),
            ]
        ),
        .testTarget(
            name: "PhotoLibraryKitTests",
            dependencies: ["PhotoLibraryKit"]
        ),
    ]
)
