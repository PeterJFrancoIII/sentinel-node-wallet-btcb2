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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(
            name: "NodePocketCore",
            dependencies: [],
            path: "Sources/NodePocketCore"
        ),
        .executableTarget(
            name: "NodePocketApp",
            dependencies: [
                "NodePocketCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/NodePocketApp"
        ),
        .testTarget(
            name: "NodePocketCoreTests",
            dependencies: ["NodePocketCore"],
            path: "Tests/NodePocketCoreTests"
        )
    ]
)

