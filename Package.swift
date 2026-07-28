// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "VirtualCompanion",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VirtualCompanion", targets: ["VirtualCompanion"])
    ],
    targets: [
        .executableTarget(
            name: "VirtualCompanion",
            path: "Sources/VirtualCompanion"
        ),
        .testTarget(
            name: "VirtualCompanionTests",
            dependencies: ["VirtualCompanion"],
            path: "Tests/VirtualCompanionTests"
        )
    ]
)
