// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Jot",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "Jot",
            dependencies: ["KeyboardShortcuts", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Jot"
        )
    ]
)
