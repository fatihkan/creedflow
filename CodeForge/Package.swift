// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CodeForge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodeForge", targets: ["CodeForge"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "CodeForge",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/CodeForge",
            resources: [
                .copy("Resources/AgentPrompts"),
                .copy("Resources/JSONSchemas"),
            ]
        ),
        .testTarget(
            name: "CodeForgeTests",
            dependencies: [
                "CodeForge",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/CodeForgeTests"
        ),
    ]
)
