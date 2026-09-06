// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FoloVibeBridge",
    platforms: [.macOS(.v14)],  // RootView 用了 macOS 14 的 toolbar(removing:)
    products: [
        .executable(name: "FoloVibeBridge", targets: ["FoloVibeBridge"]),
        .executable(name: "FoloVibeCoreTests", targets: ["FoloVibeCoreTests"]),
    ],
    targets: [
        .target(
            name: "FoloVibeCore",
            path: "Sources/FoloVibeCore"
        ),
        .executableTarget(
            name: "FoloVibeBridge",
            dependencies: ["FoloVibeCore"],
            path: "Sources/App",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "FoloVibeCoreTests",
            dependencies: ["FoloVibeCore"],
            path: "Tests"
        ),
    ]
)
