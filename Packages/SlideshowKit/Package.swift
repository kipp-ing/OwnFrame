// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SlideshowKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SlideshowKit", targets: ["SlideshowKit"]),
    ],
    dependencies: [
        .package(path: "../ImmichClient"),
        .package(path: "../ThemeKit"),
    ],
    targets: [
        .target(
            name: "SlideshowKit",
            dependencies: [
                .product(name: "ImmichClient", package: "ImmichClient"),
                .product(name: "ThemeKit", package: "ThemeKit"),
            ]
        ),
        .testTarget(
            name: "SlideshowKitTests",
            dependencies: [
                "SlideshowKit",
                .product(name: "ImmichClient", package: "ImmichClient"),
                .product(name: "ImmichClientTestSupport", package: "ImmichClient"),
                .product(name: "ThemeKitTestSupport", package: "ThemeKit"),
            ]
        ),
    ]
)
