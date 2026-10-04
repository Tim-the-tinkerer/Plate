// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Plate",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Plate", targets: ["Plate"]),
    ],
    targets: [
        .executableTarget(
            name: "Plate",
            path: "Sources/Plate"
        ),
    ]
)
