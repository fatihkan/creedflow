// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CodeForge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodeForge", targets: ["CodeForge"]),
        .executable(name: "CodeForgeTests", targets: ["CodeForgeTests"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "CodeForgeLib",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/CodeForge",
            resources: [
                .copy("Resources/AgentPrompts"),
                .copy("Resources/JSONSchemas"),
            ]
        ),
        .executableTarget(
            name: "CodeForge",
            dependencies: ["CodeForgeLib"],
            path: "Sources/App"
        ),
        .executableTarget(
            name: "CodeForgeTests",
            dependencies: [
                "CodeForgeLib",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/CodeForgeTests"
        ),
    ]
)
