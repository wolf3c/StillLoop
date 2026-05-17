// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "StillLoop",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "StillLoop", targets: ["StillLoop"]),
        .library(name: "StillLoopCore", targets: ["StillLoopCore"])
    ],
    dependencies: [
        .package(path: "../TraceMind/sdk/ios")
    ],
    targets: [
        .executableTarget(
            name: "StillLoop",
            dependencies: [
                "StillLoopCore",
                .product(name: "TraceMind", package: "ios")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .target(name: "StillLoopCore"),
        .testTarget(
            name: "StillLoopCoreTests",
            dependencies: ["StillLoopCore"]
        ),
        .testTarget(
            name: "StillLoopTests",
            dependencies: ["StillLoop"]
        )
    ]
)
