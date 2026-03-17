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
            name: "FloatRec"
        ),
        .testTarget(
            name: "FloatRecTests",
            dependencies: ["FloatRec"]
        ),
    ]
)
