// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HAControlKit",
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HAControlKit", targets: ["HAControlKit"]),
        .library(name: "HAControlMQTT", targets: ["HAControlMQTT"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server-community/mqtt-nio.git", from: "2.12.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.37.0"),
    ],
    targets: [
        .target(name: "HAControlKit"),
        .target(
            name: "HAControlMQTT",
            dependencies: [
                "HAControlKit",
                .product(name: "MQTTNIO", package: "mqtt-nio"),
            ]
        ),
        .testTarget(name: "HAControlKitTests", dependencies: ["HAControlKit"]),
        // Integration test for the real mqtt-nio transport against a live TLS broker.
        // Skipped unless MQTT_INTEGRATION=1 (never runs in CI; see the test for setup).
        .testTarget(
            name: "HAControlMQTTTests",
            dependencies: [
                "HAControlMQTT",
                "HAControlKit",
                .product(name: "MQTTNIO", package: "mqtt-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ]
        ),
    ]
)
