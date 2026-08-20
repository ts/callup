// swift-tools-version: 6.0

import PackageDescription
import Foundation

let generatedTMDBCredential = "Sources/CallupTMDB/BundledTMDBCredential.generated.swift"
let tmdbExcludes = FileManager.default.fileExists(atPath: generatedTMDBCredential)
    ? ["BundledTMDBCredential.none.swift"]
    : []

let package = Package(
    name: "Callup",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "callup", targets: ["CallupServer"]),
        .library(name: "CallupCore", targets: ["CallupCore"]),
        .library(name: "CallupAutomation", targets: ["CallupAutomation"]),
        .library(name: "CallupNewznab", targets: ["CallupNewznab"]),
        .library(name: "CallupDownloadClients", targets: ["CallupDownloadClients"]),
        .library(name: "CallupUpdates", targets: ["CallupUpdates"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", exact: "4.121.4"),
        .package(url: "https://github.com/vapor/sqlite-nio.git", exact: "1.12.9"),
    ],
    targets: [
        .target(name: "CallupCore"),
        .target(
            name: "CallupPersistence",
            dependencies: [
                "CallupCore",
                .product(name: "SQLiteNIO", package: "sqlite-nio"),
            ]
        ),
        .target(name: "CallupNewznab", dependencies: ["CallupCore"]),
        .target(name: "CallupDownloadClients", dependencies: ["CallupCore"]),
        .target(name: "CallupUpdates"),
        .target(
            name: "CallupAutomation",
            dependencies: ["CallupCore", "CallupDownloadClients", "CallupPersistence"]
        ),
        .target(name: "CallupTVMaze", dependencies: ["CallupCore"]),
        .target(
            name: "CallupTMDB",
            dependencies: ["CallupCore"],
            exclude: tmdbExcludes
        ),
        .executableTarget(
            name: "CallupServer",
            dependencies: [
                "CallupCore",
                "CallupAutomation",
                "CallupDownloadClients",
                "CallupNewznab",
                "CallupPersistence",
                "CallupTVMaze",
                "CallupTMDB",
                "CallupUpdates",
                .product(name: "Vapor", package: "vapor"),
            ],
            resources: [.copy("Resources/Web")]
        ),
        .testTarget(name: "CallupCoreTests", dependencies: ["CallupCore"]),
        .testTarget(
            name: "CallupAutomationTests",
            dependencies: ["CallupAutomation", "CallupCore"]
        ),
        .testTarget(
            name: "CallupDownloadClientsTests",
            dependencies: ["CallupCore", "CallupDownloadClients"]
        ),
        .testTarget(
            name: "CallupPersistenceTests",
            dependencies: ["CallupCore", "CallupPersistence"]
        ),
        .testTarget(
            name: "CallupNewznabTests",
            dependencies: ["CallupCore", "CallupNewznab"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "CallupTVMazeTests",
            dependencies: ["CallupCore", "CallupTVMaze"]
        ),
        .testTarget(
            name: "CallupTMDBTests",
            dependencies: ["CallupCore", "CallupTMDB"]
        ),
        .testTarget(name: "CallupUpdatesTests", dependencies: ["CallupUpdates"]),
    ]
)
