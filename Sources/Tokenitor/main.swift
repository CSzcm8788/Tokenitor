import AppKit

// 手动搭建应用入口（不依赖 .xib / @main，便于用 swift build 直接编译）。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
