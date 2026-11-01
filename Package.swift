// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TramBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TramBar", path: "Sources/TramBar")
    ]
)
