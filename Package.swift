// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ScreenRecorder",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ScreenRecorder",
            path: "Sources/ScreenRecorder"
        ),
        .testTarget(
            name: "ScreenRecorderTests",
            dependencies: ["ScreenRecorder"],
            path: "Tests/ScreenRecorderTests"
        ),
    ]
)
