// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DMAction",
    platforms: [
        .iOS(.v17),
        .watchOS(.v7),
    ],
    products: [
        .library(
            name: "DMAction",
            targets: ["DMAction"]),
    ],
    targets: [
        .target(
            name: "DMAction",
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
        .testTarget(
            name: "DMActionTests",
            dependencies: ["DMAction"],
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
