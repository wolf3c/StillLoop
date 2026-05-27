// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "StillLoop",
    defaultLocalization: "zh-Hans",
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
            exclude: [
                "Resources/Runtime"
            ],
            resources: [
                .process("Resources/AppIcon.iconset"),
                .process("Resources/Brand"),
                .process("Resources/Localizable.xcstrings"),
                .process("Resources/StillLoop.icns")
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
