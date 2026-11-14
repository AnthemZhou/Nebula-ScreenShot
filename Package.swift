// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NebulaScreenShot",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "NebulaScreenShot", targets: ["NebulaScreenShot"])],
    targets: [
        .target(name: "NebulaCore"),
        .executableTarget(name: "NebulaScreenShot", dependencies: ["NebulaCore"]),
        .testTarget(name: "NebulaCoreTests", dependencies: ["NebulaCore"])
    ],
    swiftLanguageModes: [.v5]
)
