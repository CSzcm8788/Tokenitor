import Foundation

/// 订阅档位的「可信才显示」映射：读到的值必须能对上该家**真实档位名**才返回展示文案，
/// 否则一律 nil（宁缺勿错）。账户类型（如 Copilot 的 individual）不是档位，不显示；
/// 与实际配额可能矛盾的值（如 Codex 陈旧 claim 的 free）也不显示。
enum PlanTier {

    /// Claude：来自 Claude Code 凭证 JSON 的 `subscriptionType`。
    static func claude(_ subscriptionType: String?) -> String? {
        switch subscriptionType?.lowercased() {
        case "pro":        return "Pro"
        case "max":        return "Max"
        case "team":       return "Team"
        case "enterprise": return "Enterprise"
        default:           return nil   // free / 未知 / 缺失 → 不显示
        }
    }

    /// Codex：来自 ~/.codex/auth.json 里 id_token 的 `chatgpt_plan_type` claim。
    /// free 不显示：claim 可能陈旧、且与本机实际的付费配额窗口矛盾时宁可不挂。
    static func codex(_ claim: String?) -> String? {
        switch claim?.lowercased() {
        case "plus":       return "Plus"
        case "pro":        return "Pro"
        case "team":       return "Team"
        case "business":   return "Business"
        case "enterprise": return "Enterprise"
        default:           return nil
        }
    }

    /// Copilot：来自 `copilot_internal/user` 的 `copilot_plan`。
    /// `individual` 是账户类型而非档位 → 不显示。
    static func copilot(_ plan: String?) -> String? {
        guard let p = plan?.lowercased() else { return nil }
        if p.contains("pro_plus") || p.contains("pro+") { return "Pro+" }
        if p.contains("pro") { return "Pro" }
        switch p {
        case "free":       return "Free"
        case "business":   return "Business"
        case "enterprise": return "Enterprise"
        default:           return nil
        }
    }

    // MARK: - Codex 本地读取（只解码 JWT payload 展示档位；不校验、不落盘、不外发）

    /// 读 ~/.codex/auth.json → tokens.id_token → payload 的 chatgpt_plan_type，过可信映射。
    static func codexPlanFromAuthFile() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let idToken = ((root["tokens"] as? [String: Any])?["id_token"] as? String)
            ?? (root["id_token"] as? String)
        guard let idToken,
              let claims = decodeJWTPayload(idToken),
              let auth = claims["https://api.openai.com/auth"] as? [String: Any] else { return nil }
        return codex(auth["chatgpt_plan_type"] as? String)
    }

    /// 解码 JWT 的 payload 段（base64url，无签名校验——仅用于读取展示性字段）。
    static func decodeJWTPayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
