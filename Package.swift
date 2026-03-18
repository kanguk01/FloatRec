// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FloatRec",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "FloatRec",
            targets: ["FloatRec"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "FloatRec",
            dependencies: ["Sparkle"]
        ),
        .binaryTarget(
            name: "Sparkle",
            path: "Frameworks/Sparkle.xcframework"
        ),
        .testTarget(
            name: "FloatRecTests",
            dependencies: ["FloatRec"]
        ),
    ]
)
