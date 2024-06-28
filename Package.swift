// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CaptureKitCLI",
    platforms: [
        .macOS("12.3")
    ],
    products: [
        .executable(
            name: "capturekit",
            targets: [
                "CaptureKitCLI"
            ]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "CaptureKitCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/CaptureKitCLI"
        )
    ]
)