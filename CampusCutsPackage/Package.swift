// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CampusCutsModule",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CampusCutsModule",
            targets: ["CampusCutsModule"]
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
            name: "CampusCutsModule",
            dependencies: [
                .product(name: "SocketIO", package: "socket.io-client-swift"),
            ],
            path: "ios-module/Sources/CampusCutsModule",
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
            name: "CampusCutsModuleTests",
            dependencies: ["CampusCutsModule"],
            path: "ios-module/Tests/CampusCutsModuleTests"
        )
    ]
)
