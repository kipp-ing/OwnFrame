// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OnboardingKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "OnboardingKit", targets: ["OnboardingKit"]),
    ],
    dependencies: [
        .package(path: "../ImmichClient"),
    ],
    targets: [
        .target(
            name: "OnboardingKit",
            dependencies: [
                .product(name: "ImmichClient", package: "ImmichClient"),
            ],
            resources: [.process("Localizable.xcstrings")]
        ),
        .testTarget(
            name: "OnboardingKitTests",
            dependencies: [
                "OnboardingKit",
                .product(name: "ImmichClientTestSupport", package: "ImmichClient"),
            ]
        ),
    ]
)
