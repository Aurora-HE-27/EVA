// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "EVA",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "EVA", targets: ["EVA"])
    ],
    targets: [
        .executableTarget(
            name: "EVA",
            path: "Sources/EVA"
        ),
        .testTarget(
            name: "EVATests",
            dependencies: ["EVA"],
            path: "Tests/EVATests"
        )
    ]
)
