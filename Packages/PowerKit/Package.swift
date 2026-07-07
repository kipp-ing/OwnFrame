// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PowerKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PowerKit", targets: ["PowerKit"]),
    ],
    targets: [
        .target(name: "PowerKit"),
        .testTarget(name: "PowerKitTests", dependencies: ["PowerKit"]),
    ]
)
