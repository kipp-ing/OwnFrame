// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImmichClient",
    platforms: [
        // iPadOS target for the app; macOS enables `swift test` on the host without a simulator.
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ImmichClient", targets: ["ImmichClient"]),
        .library(name: "ImmichClientTestSupport", targets: ["ImmichClientTestSupport"]),
    ],
    dependencies: [
        .package(path: "../PhotoSourceKit"),
    ],
    targets: [
        .target(
            name: "ImmichClient",
            dependencies: [
                .product(name: "PhotoSourceKit", package: "PhotoSourceKit"),
            ]
        ),
        .target(
            name: "ImmichClientTestSupport",
            dependencies: ["ImmichClient"]
        ),
        .testTarget(
            name: "ImmichClientTests",
            dependencies: [
                "ImmichClient",
                "ImmichClientTestSupport",
                .product(name: "PhotoSourceKit", package: "PhotoSourceKit"),
            ]
        ),
    ]
)
