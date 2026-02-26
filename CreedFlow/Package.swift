// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CreedFlow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CreedFlow", targets: ["CreedFlow"]),
        .executable(name: "CreedFlowMCPServer", targets: ["CreedFlowMCPServer"]),
        .executable(name: "CreedFlowTests", targets: ["CreedFlowTests"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
    ],
    targets: [
        .target(
            name: "CreedFlowLib",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/CreedFlow",
            resources: [
                .copy("Resources/AppIcon-preview.png"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CreedFlow",
            dependencies: ["CreedFlowLib"],
            path: "Sources/App",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CreedFlowMCPServer",
            dependencies: [
                "CreedFlowLib",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/MCPServer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CreedFlowTests",
            dependencies: [
                "CreedFlowLib",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/CreedFlowTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
