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
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-protobuf.git",
            exact: "1.32.0"
        ),
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            from: "2.9.0"
        ),
        .package(
            url: "https://github.com/getsentry/sentry-cocoa",
            from: "9.24.0"
        ),
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
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "StandClear",
            dependencies: [
                "StandClearCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Sentry", package: "sentry-cocoa"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                // Nothing embeds frameworks for us without an Xcode project.
                // - ../Frameworks: shipped .app bundle
                // - ../../artifacts/...: `swift run` from .build/.../release|debug
                // - ../../../../../artifacts/...: `swift test` .xctest/Contents/MacOS
                .unsafeFlags([
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker",
                    "@executable_path/../../artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64",
                    "-Xlinker", "-rpath", "-Xlinker",
                    "@executable_path/../../../../../artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64",
                ])
            ]
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
