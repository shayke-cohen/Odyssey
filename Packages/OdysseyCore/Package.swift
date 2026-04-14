// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OdysseyCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "OdysseyCore", targets: ["OdysseyCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
    ],
    targets: [
        .target(
            name: "OdysseyCore",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ]
        ),
        .testTarget(
            name: "OdysseyCoreTests",
            dependencies: ["OdysseyCore"]
        ),
    ]
)
