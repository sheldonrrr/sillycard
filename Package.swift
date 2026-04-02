// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sillycard",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Sillycard", targets: ["Sillycard"]),
    ],
    targets: [
        .executableTarget(
            name: "Sillycard",
            path: "Sources/Sillycard"
        ),
    ]
)
