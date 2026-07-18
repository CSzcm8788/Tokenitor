import AppKit

// CLI 模式：`Tokenitor --cli [--json]` 在终端打印一次配额后退出，不启动 GUI。
if CommandLine.arguments.contains("--cli") {
    CLIRunner.run(json: CommandLine.arguments.contains("--json"))
}

// 手动搭建应用入口（不依赖 .xib / @main，便于用 swift build 直接编译）。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
