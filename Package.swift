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
            // `.process` optimizes/flattens the flat asset folder; the bundled
            // web effects live in their own `Web/` dir and are `.copy`'d verbatim
            // so each .html can reference its sibling `lib/*.js` by relative path.
            resources: [.process("Resources"), .copy("Web")]
        ),
        // Minimal tests — homography math only (the correctness-critical piece).
        .testTarget(
            name: "LumoraTests",
            dependencies: ["LumoraKit"]
        ),
    ]
)
