// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PurchaseKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .tvOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PurchaseKit", targets: ["PurchaseKit"]),
    ],
    targets: [
        .target(
            name: "PurchaseKit",
            resources: [
                .process("Localizable.xcstrings"),
                // The unlock screen's live-demo photo (FR-1100-09). `.copy` keeps the file
                // addressable as UnlockDemoCliff.jpg at the bundle root, which is what
                // `UnlockDemoMedia` (and its resource-presence test) resolve.
                .copy("Resources/UnlockDemoCliff.jpg"),
            ]
        ),
        .testTarget(name: "PurchaseKitTests", dependencies: ["PurchaseKit"]),
    ]
)
