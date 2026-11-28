// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Every target compiles with these. devkit.conf repeats them in SWIFT_FLAGS.
let swiftSettings: [SwiftSetting] = [.enableUpcomingFeature("ExistentialAny")]

let package = Package(
    name: "DMAction",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "DMAction",
            targets: ["DMAction"]),
    ],
    dependencies: [
        // The tracing port and its signpost adapter, from the same family. The library imports it
        // with `package import`, outside the Domain folder, so the public interface does not name
        // it.
        .package(url: "https://github.com/nikolay-dementiev/DMCore.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "DMAction",
            dependencies: [.product(name: "DMCore", package: "DMCore")],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "DMActionTests",
            dependencies: [
                "DMAction",
                .product(name: "DMCore", package: "DMCore"),
                .product(name: "DMCoreTesting", package: "DMCore"),
            ],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
