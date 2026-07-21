import Foundation

/// 只读 CLI 模式：`Tokenitor --cli [--json]`。
/// 复用与 GUI 完全相同的 provider 层读一次配额、打印、退出——不启动任何 UI、不常驻。
/// 供脚本 / tmux 状态栏 / 自动化使用；建议 `ln -s` 到 PATH（见 README）。
enum CLIRunner {
    static func run(json: Bool) -> Never {
        let providers = AIKind.allCases.map { $0.makeProvider() }.filter { $0.enabled }
        var results: [String: ProviderSnapshot] = [:]
        let lock = NSLock()
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            p.fetch { snap in
                lock.lock(); results[p.displayName] = snap; lock.unlock()
                group.leave()
            }
        }
        // 云端源最长等 30s（限流重试等极端情况下不挂死终端）
        _ = group.wait(timeout: .now() + 30)
        let ordered = providers.compactMap { results[$0.displayName] }.filter { !$0.hidden }
        if json { printJSON(ordered) } else { printText(ordered) }
        exit(0)
    }

    // MARK: - 文本输出（人读）

    private static func printText(_ snaps: [ProviderSnapshot]) {
        guard !snaps.isEmpty else {
            print("No active AI tools detected (nothing installed/signed in, or all disabled in Settings).")
            return
        }
        for s in snaps {
            var head = "\(s.name) [\(status(s))]"
            if let plan = s.plan, !plan.isEmpty { head += " [\(plan)]" }
            if s.resetCreditsUnlimited { head += " [resets ∞]" }
            else if let n = s.resetCredits { head += " [resets ×\(n)]" }
            print(head)
            if let t = s.dataAsOf, Date().timeIntervalSince(t) > 180 {
                print("  data age: \(formatUpdatedAgo(t, english: true))")
            }
            if !s.ok, let err = s.error {
                print("  \(err)")
                continue
            }
            for w in s.windows {
                let label = w.label.padding(toLength: max(8, w.label.count), withPad: " ", startingAt: 0)
                var line = "  \(label) \(String(format: "%3d", Int(w.remainingPercent.rounded())))% left"
                let cd = formatCountdown(to: w.resetsAt, english: true)
                if !cd.isEmpty { line += "   resets in \(cd)" }
                print(line)
            }
        }
    }

    // MARK: - JSON 输出（机器读；键名稳定，供脚本依赖）

    private static func printJSON(_ snaps: [ProviderSnapshot]) {
        print(jsonString(snaps))
    }

    /// 生成 JSON 文本（键名对脚本是稳定契约）。internal 供测试断言字段形状。
    static func jsonString(_ snaps: [ProviderSnapshot]) -> String {
        let iso = ISO8601DateFormatter()
        let arr: [[String: Any]] = snaps.map { s in
            var d: [String: Any] = [
                "name": s.name,
                "status": status(s),
                "windows": s.windows.map { w -> [String: Any] in
                    var wd: [String: Any] = [
                        "label": w.label,
                        "remaining_percent": Int(w.remainingPercent.rounded()),
                    ]
                    if let r = w.resetsAt { wd["resets_at"] = iso.string(from: r) }
                    return wd
                },
            ]
            if let plan = s.plan, !plan.isEmpty { d["plan"] = plan }
            if s.resetCreditsUnlimited { d["reset_credits_unlimited"] = true }
            if let n = s.resetCredits { d["reset_credits"] = n }
            if let t = s.dataAsOf { d["data_as_of"] = iso.string(from: t) }
            if let err = s.error { d["error"] = err }
            return d
        }
        guard let data = try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    private static func status(_ s: ProviderSnapshot) -> String {
        s.ok ? (s.isStale ? "cached" : "live") : "offline"
    }
}
