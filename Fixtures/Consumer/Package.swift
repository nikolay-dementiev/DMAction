// swift-tools-version: 6.0

import PackageDescription

// A package that uses DMAction the way an app or a downstream library does. It exists to
// be compiled: when a public declaration it uses changes shape, it stops building.
let package = Package(
    name: "Consumer",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "Consumer", targets: ["Consumer"])
    ],
    dependencies: [
        .package(name: "DMAction", path: "../..")
    ],
    targets: [
        .target(
            name: "Consumer",
            dependencies: [
                .product(name: "DMAction", package: "DMAction")
            ]
        )
    ]
)
