// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppIntentsKit",
    platforms: [
        // iPadOS target for the app; macOS enables `swift test` on the host without a simulator.
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "AppIntentsKit", targets: ["AppIntentsKit"]),
        .library(name: "AppIntentsTestSupport", targets: ["AppIntentsTestSupport"]),
    ],
    dependencies: [
        // The HAControlKit PRODUCT only (control protocols + PhotoReport) — never
        // HAControlMQTT; the intents layer must not pull the MQTT transport.
        .package(path: "../HAControlKit"),
    ],
    targets: [
        .target(
            name: "AppIntentsKit",
            dependencies: [.product(name: "HAControlKit", package: "HAControlKit")]
        ),
        .target(
            name: "AppIntentsTestSupport",
            dependencies: [
                "AppIntentsKit",
                .product(name: "HAControlKit", package: "HAControlKit"),
            ]
        ),
        .testTarget(
            name: "AppIntentsKitTests",
            dependencies: ["AppIntentsKit", "AppIntentsTestSupport"]
        ),
    ]
)
