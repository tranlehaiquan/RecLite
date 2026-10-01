// swift-tools-version: 5.9
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
            path: "Sources/ScreenRecorder",
            swiftSettings: [
                .unsafeFlags([
                    "-strict-concurrency=minimal",
                    "-load-plugin-library",
                    "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib",
                ])
            ]
        ),
        .testTarget(
            name: "ScreenRecorderTests",
            dependencies: ["ScreenRecorder"],
            path: "Tests/ScreenRecorderTests"
        ),
    ]
)
