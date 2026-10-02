// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Every target compiles with these. Scripts/check-api.sh repeats them in SWIFT_FLAGS.
let swiftSettings: [SwiftSetting] = [.enableUpcomingFeature("ExistentialAny")]

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
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "DMActionTests",
            dependencies: ["DMAction"],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
