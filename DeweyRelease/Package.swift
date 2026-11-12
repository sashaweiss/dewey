// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DeweyRelease",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "dewey-release", targets: ["DeweyRelease"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "1.0.1"),
    ],
    targets: [
        .executableTarget(
            name: "DeweyRelease",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Subprocess", package: "swift-subprocess"),
            ],
        ),
        .testTarget(name: "DeweyReleaseTests", dependencies: ["DeweyRelease"]),
    ],
)
