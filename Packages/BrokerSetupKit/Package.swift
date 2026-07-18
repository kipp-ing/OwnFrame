// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BrokerSetupKit",
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [.library(name: "BrokerSetupKit", targets: ["BrokerSetupKit"])],
    dependencies: [
        .package(path: "../HAControlKit"),
    ],
    targets: [
        .target(name: "BrokerSetupKit", dependencies: ["HAControlKit"]),
        .testTarget(name: "BrokerSetupKitTests", dependencies: ["BrokerSetupKit"]),
    ]
)
