// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NodePocketBTCB2",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "NodePocketCore",
            targets: ["NodePocketCore"]
        ),
        .executable(
            name: "NodePocketApp",
            targets: ["NodePocketApp"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "NodePocketCore",
            dependencies: [],
            path: "Sources/NodePocketCore"
        ),
        .executableTarget(
            name: "NodePocketApp",
            dependencies: ["NodePocketCore"],
            path: "Sources/NodePocketApp"
        ),
        .testTarget(
            name: "NodePocketCoreTests",
            dependencies: ["NodePocketCore"],
            path: "Tests/NodePocketCoreTests"
        )
    ]
)
