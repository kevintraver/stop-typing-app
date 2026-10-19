// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StopTypingCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "StopTypingCore", targets: ["StopTypingCore"]),
    ],
    targets: [
        .target(name: "StopTypingCore"),
        .testTarget(name: "StopTypingCoreTests", dependencies: ["StopTypingCore"]),
    ]
)
