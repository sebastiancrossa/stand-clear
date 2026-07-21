// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StandClear",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "StandClear", targets: ["StandClear"]),
        .library(name: "StandClearCore", targets: ["StandClearCore"]),
    ],
    targets: [
        .target(
            name: "StandClearCore",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "StandClear",
            dependencies: ["StandClearCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "StandClearCoreTests",
            dependencies: ["StandClearCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "StandClearTests",
            dependencies: ["StandClear"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
