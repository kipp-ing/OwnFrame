// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SlideshowKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17), .tvOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SlideshowKit", targets: ["SlideshowKit"]),
    ],
    dependencies: [
        .package(path: "../PhotoSourceKit"),
        .package(path: "../ThemeKit"),
        // Test-only: the dual-backend engine gate (SC-900-03) drives a real
        // PhotoLibraryProvider over the shared gateway fake. PhotoLibraryKit does not
        // depend on SlideshowKit, so this dependency direction introduces no cycle.
        .package(path: "../PhotoLibraryKit"),
    ],
    targets: [
        .target(
            name: "SlideshowKit",
            dependencies: [
                .product(name: "PhotoSourceKit", package: "PhotoSourceKit"),
                .product(name: "ThemeKit", package: "ThemeKit"),
            ]
        ),
        .testTarget(
            name: "SlideshowKitTests",
            dependencies: [
                "SlideshowKit",
                .product(name: "PhotoSourceKit", package: "PhotoSourceKit"),
                .product(name: "PhotoSourceTestSupport", package: "PhotoSourceKit"),
                .product(name: "PhotoLibraryKit", package: "PhotoLibraryKit"),
                .product(name: "PhotoLibraryTestSupport", package: "PhotoLibraryKit"),
                .product(name: "ThemeKitTestSupport", package: "ThemeKit"),
            ]
        ),
    ]
)
