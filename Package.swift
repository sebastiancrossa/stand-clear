// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SubwayBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "SubwayBar", targets: ["SubwayBar"]),
        .library(name: "SubwayBarCore", targets: ["SubwayBarCore"]),
    ],
    targets: [
        .target(
            name: "SubwayBarCore",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "SubwayBar",
            dependencies: ["SubwayBarCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SubwayBarCoreTests",
            dependencies: ["SubwayBarCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

