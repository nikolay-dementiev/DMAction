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
    dependencies: [
        .package(url: "https://github.com/GayleDunham/SwiftLintPlugin.git", branch: "main")
    ],
    targets: [
        .target(
            name: "DMAction",
            path: "Sources",
            plugins: [ .plugin(name: "SwiftLintBuildTool", package: "SwiftLintPlugin") ]),
        .testTarget(
            name: "DMActionTests",
            dependencies: ["DMAction"],
            path: "Tests",
            plugins: [ .plugin(name: "SwiftLintBuildTool", package: "SwiftLintPlugin") ]
        ),
    ]
)
