// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Cloner",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Cloner", targets: ["Cloner"])
    ],
    targets: [
        .executableTarget(name: "Cloner", path: "Sources/Cloner")
    ]
)
