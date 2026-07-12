// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lumora",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure, UI-free geometry + model core. Fully unit-testable.
        .target(name: "LumoraKit"),
        // The macOS SwiftUI app.
        .executableTarget(
            name: "Lumora",
            dependencies: ["LumoraKit"],
            resources: [.process("Resources")]
        ),
        // Minimal tests — homography math only (the correctness-critical piece).
        .testTarget(
            name: "LumoraTests",
            dependencies: ["LumoraKit"]
        ),
    ]
)
