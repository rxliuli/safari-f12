// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SafariF12",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SafariF12",
            path: "Sources/SafariF12"
        )
    ]
)
