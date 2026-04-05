// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoxOps",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoxOpsCore", targets: ["VoxOpsCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "VoxOpsCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "VoxOpsCoreTests",
            dependencies: ["VoxOpsCore"]
        ),
    ]
)
