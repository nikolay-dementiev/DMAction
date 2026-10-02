// swift-tools-version: 6.0

import PackageDescription

// Uses of DMAction across isolation domains that the Swift 6 compiler rejects today.
// Scripts/check-manifest.sh builds each target on its own and expects it to fail: a target
// that starts to compile means the documented concurrency limits have changed.
let shapes = [
    "TaskInNonisolatedClosure",
    "DetachedTask",
    "ContinuationBridge",
    "GlobalStorage",
    "SendableConformance"
]

let package = Package(
    name: "Rejected",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "DMAction", path: "../..")
    ],
    targets: shapes.map { shape in
        .target(name: shape, dependencies: [.product(name: "DMAction", package: "DMAction")])
    }
)
