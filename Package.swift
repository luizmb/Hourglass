// swift-tools-version: 6.3
import PackageDescription

// swift-docc-plugin only generates documentation (run on macOS in CI via the Documentation
// workflow). Its command plugin is built by `swift build` on Windows and fails there, so exclude
// the dependency on Windows hosts — it is not needed to build or test the package.
var dependencies: [Package.Dependency] = []
#if !os(Windows)
    dependencies.append(.package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"))
#endif

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
    dependencies: dependencies,
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
