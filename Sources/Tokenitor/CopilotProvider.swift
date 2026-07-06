import Foundation

/// 读取 GitHub Copilot 的「月度高级用量」（premium interactions / AI Credits）。
///
/// 口径（2026-06 起）：每个 Copilot 套餐每月含固定额度的「高级交互」（premium
/// interactions），每月 1 号 00:00 UTC 重置；chat / completions 对付费套餐通常不限量。
///
/// 取数：本机登录态在 `~/.config/github-copilot/`（`apps.json` 新版 / `hosts.json` 旧版，
/// 含 `oauth_token`，gho_ 开头）。用该 token 调 GitHub 内置端点
/// `GET https://api.github.com/copilot_internal/user`，读 `quota_snapshots.premium_interactions`
/// 的 `percent_remaining` 与顶层 `quota_reset_date`。个人 Pro 订阅可直接用 gho_ token 访问，
/// 无需额外换取会话 token。
///
/// ⚠️ 该端点为 GitHub 未公开的内部接口（编辑器插件同款）；仅用用户本人 token 读本人用量、
///    只读、不改任何数据。属「非官方端点」，失效时优雅降级、不影响其它工具。
final class CopilotProvider: UsageProvider {
    let displayName = "Copilot"
    var enabled: Bool { Settings.shared.copilotEnabled }

    func fetch(completion: @escaping (ProviderSnapshot) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            // token 来源：device flow 授权（钥匙串）优先 → 本地编辑器登录态兜底；都没有 → 隐藏
            guard let token = CopilotAuth.shared.storedToken() else {
                completion(.absent(self.displayName)); return
            }

            self.request("https://api.github.com/copilot_internal/user", token: token) { sc, root in
                guard sc == 200, let root = root else {
                    // 已登录但拿不到用量（端点变动 / 限流）→ 软提示，不红错
                    completion(ProviderSnapshot(name: self.displayName, windows: [], ok: true,
                                                error: nil, note: "已登录（用量获取失败）"))
                    return
                }
                completion(self.parse(root))
            }
        }
    }

    // MARK: - 解析

    private func parse(_ root: [String: Any]) -> ProviderSnapshot {
        let plan = (root["copilot_plan"] as? String)?
            .replacingOccurrences(of: "_", with: " ")
        let reset = self.resetDate(root["quota_reset_date"])
        let snaps = root["quota_snapshots"] as? [String: Any]

        // 主口径：premium_interactions（用户最关心的高级/付费额度）；缺失时退回 chat。
        let snap = (snaps?["premium_interactions"] as? [String: Any])
            ?? (snaps?["chat"] as? [String: Any])

        var windows: [UsageWindow] = []
        var note: String

        if let snap = snap {
            if (snap["unlimited"] as? Bool) == true {
                // 不限量套餐：无进度条，仅提示
                note = planNote(plan, extra: "高级用量不限量")
            } else {
                let pctRemain = JSON.double(snap["percent_remaining"])
                    ?? (100 - (JSON.double(snap["percent_used"]) ?? 0))
                let used = max(0, min(100, 100 - max(0, min(100, pctRemain))))
                windows = [UsageWindow(usedPercent: used, resetsAt: reset, label: "premium")]

                var extra = "高级用量"
                if let ent = JSON.double(snap["entitlement"]), ent > 0 {
                    let rem = JSON.double(snap["remaining"]) ?? JSON.double(snap["quota_remaining"])
                    if let rem = rem {
                        extra = String(format: "高级用量 剩 %.0f/%.0f", max(0, rem), ent)
                    } else {
                        extra = String(format: "高级用量 额度 %.0f/月", ent)
                    }
                }
                note = planNote(plan, extra: extra)
            }
        } else {
            note = planNote(plan, extra: "每月 1 号重置")
        }

        return ProviderSnapshot(name: displayName, windows: windows, ok: true, error: nil, note: note)
    }

    private func planNote(_ plan: String?, extra: String) -> String {
        if let plan = plan, !plan.isEmpty {
            return "\(plan.capitalized) · \(extra)"
        }
        return extra
    }

    /// "2026-08-01" → 该日 00:00 UTC。
    private func resetDate(_ any: Any?) -> Date? {
        guard let s = any as? String, !s.isEmpty else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: String(s.prefix(10)))
    }

    // MARK: - HTTP

    /// 原生异步回调（不再用信号量把 URLSession 强行同步化、阻塞 GCD 工作线程）。
    private func request(_ url: String, token: String,
                         completion: @escaping (Int, [String: Any]?) -> Void) {
        guard let u = URL(string: url) else { completion(-1, nil); return }
        var req = URLRequest(url: u)
        req.httpMethod = "GET"
        req.timeoutInterval = 12
        // 诚实标识自己，不伪装成官方 GitHub Copilot 客户端（合规取舍）。
        // 该端点可能因非官方客户端而拒绝/限流——那属于预期内的优雅降级（见 fetch 的软失败分支）。
        req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
        req.setValue(AppInfo.userAgent, forHTTPHeaderField: "Editor-Version")
        req.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            var json: [String: Any]? = nil
            if let data = data {
                DebugLog.dump("copilot", data)
                json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            completion(status, json)
        }.resume()
    }
}
