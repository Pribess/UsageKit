// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "UsageKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.8.1")
    ],
    targets: [
        .executableTarget(
            name: "UsageKit",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/UsageKit",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "UsageKitTests",
            dependencies: ["UsageKit"],
            path: "Tests/UsageKitTests"
        )
    ]
)
