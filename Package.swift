// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Keyspace",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Keyspace", path: "Sources/Keyspace")
    ]
)
