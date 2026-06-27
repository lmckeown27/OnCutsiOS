// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AvilaPlatformsModule",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AvilaPlatformsModule",
            targets: ["AvilaPlatformsModule"]
        ),
        .library(
            name: "Core",
            targets: ["Core"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/stripe/stripe-ios", from: "24.0.0"),
    ],
    targets: [
        .target(
            name: "AvilaPlatformsModule",
            dependencies: [],
            path: "ios-module/Sources/AvilaPlatformsModule",
            resources: [.process("Resources")]
        ),
        .target(
            name: "Core",
            dependencies: [
                .product(name: "StripePaymentSheet", package: "stripe-ios"),
                .product(name: "StripeApplePay", package: "stripe-ios"),
            ],
            path: "ios-module/Sources/Core"
        ),
        .testTarget(
            name: "AvilaPlatformsModuleTests",
            dependencies: ["AvilaPlatformsModule"],
            path: "ios-module/Tests/AvilaPlatformsModuleTests"
        )
    ]
)
