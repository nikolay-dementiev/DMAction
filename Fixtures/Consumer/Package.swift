// swift-tools-version: 6.0

import PackageDescription

// A package that uses DMAction the way an app or a downstream library does. It exists to
// be compiled: when a public declaration it uses changes shape, it stops building.
let package = Package(
    name: "Consumer",
    platforms: [
        .iOS(.v17),
        // A package that depends on DMAction for watchOS declares at least its floor.
        .watchOS(.v7)
    ],
    products: [
        .library(name: "Consumer", targets: ["Consumer", "ConsumerStrict"])
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
        ),
        // The same kind of use under the setting that DMAction itself builds with. Neither
        // manifest of a dependency's target configures the target of its consumer, so a consumer
        // that turns ExistentialAny on is checked here.
        .target(
            name: "ConsumerStrict",
            dependencies: [
                .product(name: "DMAction", package: "DMAction")
            ],
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        )
    ]
)
