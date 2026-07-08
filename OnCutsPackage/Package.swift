// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OnCutsModule",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "OnCutsModule",
            targets: ["OnCutsModule"]
        ),
        .library(
            name: "Core",
            targets: ["Core"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/socketio/socket.io-client-swift", from: "16.1.0"),
        .package(url: "https://github.com/stripe/stripe-ios", from: "24.0.0"),
    ],
    targets: [
        .target(
            name: "OnCutsModule",
            dependencies: [
                .product(name: "SocketIO", package: "socket.io-client-swift"),
            ],
            path: "ios-module/Sources/OnCutsModule",
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
            name: "OnCutsModuleTests",
            dependencies: ["OnCutsModule"],
            path: "ios-module/Tests/OnCutsModuleTests"
        )
    ]
)
