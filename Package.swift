// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Callup",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "callup", targets: ["CallupServer"]),
        .library(name: "CallupCore", targets: ["CallupCore"]),
        .library(name: "CallupNewznab", targets: ["CallupNewznab"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", exact: "4.121.4"),
    ],
    targets: [
        .target(name: "CallupCore"),
        .target(name: "CallupNewznab", dependencies: ["CallupCore"]),
        .target(name: "CallupTVMaze", dependencies: ["CallupCore"]),
        .executableTarget(
            name: "CallupServer",
            dependencies: [
                "CallupCore",
                "CallupNewznab",
                "CallupTVMaze",
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
        .testTarget(name: "CallupCoreTests", dependencies: ["CallupCore"]),
        .testTarget(
            name: "CallupNewznabTests",
            dependencies: ["CallupCore", "CallupNewznab"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "CallupTVMazeTests",
            dependencies: ["CallupCore", "CallupTVMaze"]
        ),
    ]
)
