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
        .target(
            name: "SillycardKit",
            dependencies: [],
            path: "Sources/Sillycard",
            exclude: ["Sillycard.entitlements"],
            resources: [
                .process("Assets.xcassets"),
                .copy("Resources/Meo.png"),
                .copy("Resources/cat_banner.png"),
            ]
        ),
        .executableTarget(
            name: "EmbedMeo",
            dependencies: ["SillycardKit"],
            path: "Tools/EmbedMeo"
        ),
        .executableTarget(
            name: "Sillycard",
            dependencies: ["SillycardKit"],
            path: "Sources/SillycardApp"
        ),
        .testTarget(
            name: "SillycardSampleTests",
            dependencies: ["SillycardKit"],
            path: "Tests/SillycardSampleTests"
        ),
    ]
)
