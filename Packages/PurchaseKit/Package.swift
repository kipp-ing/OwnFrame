// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PurchaseKit",
    platforms: [
        .iOS(.v17),
        .tvOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PurchaseKit", targets: ["PurchaseKit"]),
    ],
    targets: [
        .target(name: "PurchaseKit"),
        .testTarget(name: "PurchaseKitTests", dependencies: ["PurchaseKit"]),
    ]
)
