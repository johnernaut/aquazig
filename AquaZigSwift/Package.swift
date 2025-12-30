// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AquaZig",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "AquaZig",
            targets: ["AquaZig"]
        )
    ],
    targets: [
        .target(
            name: "AquaZig",
            dependencies: ["CAquaZig"],
            path: "Sources/AquaZig"
        ),
        .binaryTarget(
            name: "CAquaZig",
            path: "../build/AquaZig.xcframework"
        )
    ]
)
