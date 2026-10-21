// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "cli-manager",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CLIManagerKit", targets: ["CLIManagerKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.7.1")
    ],
    targets: [
        .target(
            name: "CLIManagerKit",
            dependencies: [],
            path: "Sources/CLIManagerKit"
        ),
        .executableTarget(
            name: "cli-manager",
            dependencies: [
                "CLIManagerKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/CLIManager"
        ),
        .testTarget(
            name: "CLIManagerTests",
            dependencies: ["cli-manager", "CLIManagerKit"],
            path: "Tests/CLIManagerTests"
        )
    ]
)
