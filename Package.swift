// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "zoom-hooks",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .executable(name: "zoom-hooks", targets: ["zoom-hooks"])
    ],
    targets: [
        .executableTarget(
            name: "zoom-hooks",
            swiftSettings: [
                // Treat warnings as errors to keep the codebase clean.
                .unsafeFlags(["-warnings-as-errors"])
            ]
        )
    ]
)