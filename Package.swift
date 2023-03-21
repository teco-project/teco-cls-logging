// swift-tools-version: 5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "teco-cls-logging",
    platforms: [.macOS(.v10_15), .iOS(.v13), .watchOS(.v6), .tvOS(.v13)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "TecoCLSLogging",
            targets: ["TecoCLSLogging"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apple/swift-log.git", from: "1.2.1"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.21.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.0.0"),
        .package(url: "https://github.com/teco-project/teco-core.git", .upToNextMinor(from: "0.5.0-beta.4")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "TecoCLSLogging",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "TecoSigner", package: "teco-core"),
            ],
            exclude: ["cls.proto"]
        ),
        .testTarget(
            name: "TecoCLSLoggingTests",
            dependencies: [
                "TecoCLSLogging",
            ]),
    ]
)
