// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Hourglass",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Hourglass", targets: ["Hourglass"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        .target(
            name: "Hourglass",
            dependencies: []
        ),
        .testTarget(
            name: "HourglassTests",
            dependencies: ["Hourglass"]
        ),
    ]
)
