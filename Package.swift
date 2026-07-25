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
            path: "Tests/TokenitorTests",
            // Golden fixtures：各源真实结构的**脱敏**样本（只留解析器读的字段与数字，
            // 无对话内容/会话 ID/凭证）。厂商改 schema 时，更新 fixture 即可让测试指出断点。
            resources: [.copy("Fixtures")]
        )
    ]
)
