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
        .executable(name: "StandClearStaticDataBuilder", targets: ["StandClearStaticDataBuilder"]),
    ],
    targets: [
        .target(
            name: "StandClearStaticDataCompiler",
            dependencies: ["StandClearCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "StandClearStaticDataBuilder",
            dependencies: ["StandClearStaticDataCompiler"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
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
        .testTarget(
            name: "StandClearStaticDataCompilerTests",
            dependencies: ["StandClearStaticDataCompiler", "StandClearCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
