// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let isCI = ProcessInfo.processInfo.environment["CI_ENV"] == "true"

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
            plugins: isCI ? [] : [.plugin(name: "SwiftLintBuildTool", package: "SwiftLintPlugin")]
        ),
        .testTarget(
            name: "DMActionTests",
            dependencies: ["DMAction"],
            path: "Tests",
            plugins: isCI ? [] : [.plugin(name: "SwiftLintBuildTool", package: "SwiftLintPlugin")]
        ),
    ]
)
