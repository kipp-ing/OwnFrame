// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotoLibraryKit",
    platforms: [
        // iPadOS target for the app; macOS enables `swift test` on the host without a simulator
        // (all logic sits behind PhotoLibraryGateway — only PHKitGateway touches PhotoKit).
        // tvOS is a compile-only target (topic 1000, SC-1000-04): the whole package must build
        // for a tvOS destination even though the PhotoKit adapter is never linked into the tvOS
        // app and the limited-library picker is compiled out there.
        .iOS(.v17),
        .tvOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PhotoLibraryKit", targets: ["PhotoLibraryKit"]),
        .library(name: "PhotoLibraryTestSupport", targets: ["PhotoLibraryTestSupport"]),
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
        // The scriptable gateway fake, shared so downstream suites (the SlideshowKit
        // dual-backend gate, SC-900-03) can drive a real provider over it.
        .target(
            name: "PhotoLibraryTestSupport",
            dependencies: [
                "PhotoLibraryKit",
                .product(name: "PhotoSourceKit", package: "PhotoSourceKit"),
            ]
        ),
        .testTarget(
            name: "PhotoLibraryKitTests",
            dependencies: ["PhotoLibraryKit", "PhotoLibraryTestSupport"]
        ),
    ]
)
