// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FreeRDPLauncher",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FreeRDPLauncher",
            path: "Sources/FreeRDPLauncher"
        )
    ]
)
