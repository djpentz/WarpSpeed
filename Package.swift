// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WarpSpeed",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WarpSpeed", targets: ["WarpSpeed"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "WarpSpeed",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/WarpSpeed"
        )
    ]
)
