// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Tokenitor",
    platforms: [
        .macOS(.v13)   // 全原生 UI（Form(.grouped) / NavigationStack / LabeledContent）需 macOS 13+
    ],
    targets: [
        .executableTarget(
            name: "Tokenitor",
            path: "Sources/Tokenitor"
        ),
        .testTarget(
            name: "TokenitorTests",
            dependencies: ["Tokenitor"],
            path: "Tests/TokenitorTests"
        )
    ]
)
