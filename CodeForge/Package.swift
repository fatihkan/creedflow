// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodeForge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodeForge", targets: ["CodeForge"]),
        .executable(name: "CodeForgeMCPServer", targets: ["CodeForgeMCPServer"]),
        .executable(name: "CodeForgeTests", targets: ["CodeForgeTests"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
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
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CodeForge",
            dependencies: ["CodeForgeLib"],
            path: "Sources/App",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CodeForgeMCPServer",
            dependencies: [
                "CodeForgeLib",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/MCPServer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CodeForgeTests",
            dependencies: [
                "CodeForgeLib",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/CodeForgeTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
