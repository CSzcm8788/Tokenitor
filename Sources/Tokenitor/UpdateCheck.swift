import AppKit

/// 「检查更新」：**仅手动触发**，比对 GitHub 最新 release 的 tag 与本机版本。
/// 刻意保持最简：不后台轮询、不自动下载安装、不引入 Sparkle 之类框架——
/// 只连发布宿主 GitHub（本应用本就托管在此），与「无自有服务器、零上传」的承诺一致。
enum UpdateCheck {
    private static let latestAPI = "https://api.github.com/repos/CSzcm8788/Tokenitor/releases/latest"
    private static let releasesPage = "https://github.com/CSzcm8788/Tokenitor/releases/latest"

    /// 语义化版本比较：`1.5.10` > `1.5.9`（字符串比较会判错，故按段比数值）。
    /// 段数不同按缺位补 0（`1.6` 与 `1.6.0` 等价）。internal 供测试。
    static func isNewer(_ remote: String, than local: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: ".")
                .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let r = parts(remote), l = parts(local)
        for i in 0..<max(r.count, l.count) {
            let a = i < r.count ? r[i] : 0
            let b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// 从 releases/latest 的 JSON 里取 tag（`tag_name`，形如 `v1.5.4`）。internal 供测试。
    static func parseTag(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String, !tag.isEmpty else { return nil }
        return tag
    }

    /// 手动检查：取到结果后弹一次原生 alert（有新版给「去下载」按钮）。
    static func checkNow() {
        guard let url = URL(string: latestAPI) else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")   // 诚实 UA，同其余请求
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                guard let data, let tag = parseTag(data), err == nil else {
                    present(title: L("检查更新失败", "Couldn\u{2019}t check for updates"),
                            body: L("请稍后再试，或直接打开发布页查看。",
                                    "Please try again later, or open the releases page."),
                            offerDownload: true)
                    return
                }
                if isNewer(tag, than: AppInfo.version) {
                    present(title: L("有新版本 \(tag)", "Version \(tag) is available"),
                            body: L("当前版本 \(AppInfo.version)。前往发布页下载新版 DMG（或用 Homebrew 升级）。",
                                    "You\u{2019}re on \(AppInfo.version). Download the new DMG from the releases page (or upgrade via Homebrew)."),
                            offerDownload: true)
                } else {
                    present(title: L("已是最新版本", "You\u{2019}re up to date"),
                            body: L("当前版本 \(AppInfo.version)。", "Current version: \(AppInfo.version)."),
                            offerDownload: false)
                }
            }
        }.resume()
    }

    private static func present(title: String, body: String, offerDownload: Bool) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body
        if offerDownload {
            a.addButton(withTitle: L("去下载", "Open Releases"))
            a.addButton(withTitle: L("好", "OK"))
        } else {
            a.addButton(withTitle: L("好", "OK"))
        }
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn, offerDownload,
           let u = URL(string: releasesPage) {
            NSWorkspace.shared.open(u)
        }
    }
}
