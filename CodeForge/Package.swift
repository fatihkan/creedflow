// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Creed",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Creed", targets: ["Creed"]),
        .executable(name: "CreedMCPServer", targets: ["CreedMCPServer"]),
        .executable(name: "CreedTests", targets: ["CreedTests"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
    ],
    targets: [
        .target(
            name: "CreedLib",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/Creed",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Creed",
            dependencies: ["CreedLib"],
            path: "Sources/App",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CreedMCPServer",
            dependencies: [
                "CreedLib",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/MCPServer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CreedTests",
            dependencies: [
                "CreedLib",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/CreedTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
