// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FoloVibeBridge",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FoloVibeBridge",
            path: "Sources",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
