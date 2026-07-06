import Foundation
import Security

/// GitHub OAuth **Device Flow**：用户显式授权拿 `gho_` token，存钥匙串，供 Copilot 用量读取。
/// Client ID 为公开值（device flow 无需 client secret），可安全内置于开源代码。
/// 授权路径比"直接读编辑器落盘 token"更正当（用户在 GitHub 官方页面明确同意）。
final class CopilotAuth {
    static let shared = CopilotAuth()

    private let clientID = "Ov23li5uzh4zEjvJTwqk"
    private let scope = "read:user"

    // 本应用自己的钥匙串条目（与 Claude 区分）
    private let kcService = "com.tokenitor.app"
    private let kcAccount = "copilot-oauth-token"

    private let configDir: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/github-copilot").path
    }()

    // MARK: - token 读取（钥匙串优先 → 本地编辑器登录态兜底）

    /// 供 CopilotProvider 用：优先用 device flow 授权后存进钥匙串的 token；
    /// 没有则退回读 ~/.config/github-copilot（编辑器插件已登录时的本地 token）。
    func storedToken() -> String? {
        if let t = keychainLoad(), !t.isEmpty { return t }
        return localFileToken()
    }

    /// 是否已通过 device flow 授权（钥匙串里有 token）。
    var isAuthorized: Bool { (keychainLoad()?.isEmpty == false) }

    func signOut() { keychainDelete() }

    private func localFileToken() -> String? {
        for file in ["apps.json", "hosts.json"] {
            let path = (configDir as NSString).appendingPathComponent(file)
            guard let data = FileManager.default.contents(atPath: path),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }
            for (key, val) in obj {
                guard key.contains("github.com"), let entry = val as? [String: Any],
                      let tok = entry["oauth_token"] as? String, tok.count > 10 else { continue }
                return tok
            }
        }
        return nil
    }

    // MARK: - Device Flow

    struct DeviceCode {
        let deviceCode: String
        let userCode: String
        let verificationURI: String
        let interval: Int
        let expiresIn: Int
    }

    /// 跑完整 device flow：请求设备码 → onCode 回调（UI 展示 user_code + 打开授权页）
    /// → 轮询拿 token → 存钥匙串。回调都在后台线程，UI 层自己切主线程。
    func beginDeviceFlow(onCode: @escaping (_ userCode: String, _ verifyURL: String) -> Void,
                         completion: @escaping (_ ok: Bool, _ message: String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let dc = self.requestDeviceCode() else {
                completion(false, "获取设备码失败（检查网络，以及 OAuth App 是否已勾选 Enable Device Flow）")
                return
            }
            onCode(dc.userCode, dc.verificationURI)
            let deadline = Date().addingTimeInterval(Double(dc.expiresIn))
            self.pollLoop(deviceCode: dc.deviceCode, interval: max(dc.interval, 5),
                          deadline: deadline, completion: completion)
        }
    }

    /// 轮询一轮；pending 时用 asyncAfter 续约 —— 不用 Thread.sleep 占住 GCD 线程
    /// （device flow 最长可轮 15 分钟，占死一个工作线程会加剧线程池饥饿）。
    private func pollLoop(deviceCode: String, interval: Int, deadline: Date,
                          completion: @escaping (_ ok: Bool, _ message: String?) -> Void) {
        guard Date() < deadline else { completion(false, "授权超时，请重试"); return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(interval)) {
            let (token, err) = self.pollToken(deviceCode: deviceCode)
            if let token {
                self.keychainSave(token)
                completion(true, nil)
                return
            }
            switch err {
            case "authorization_pending", nil:   // 暂态/等待授权 → 继续轮询
                self.pollLoop(deviceCode: deviceCode, interval: interval,
                              deadline: deadline, completion: completion)
            case "slow_down":
                self.pollLoop(deviceCode: deviceCode, interval: interval + 5,
                              deadline: deadline, completion: completion)
            case let e?:
                completion(false, self.friendly(e))
            }
        }
    }

    private func friendly(_ e: String) -> String {
        switch e {
        case "access_denied": return "已在浏览器取消授权"
        case "expired_token": return "验证码已过期，请重试"
        case "incorrect_client_credentials": return "Client ID 有误"
        case "device_flow_disabled": return "该 OAuth App 未开启 Device Flow（去 GitHub 勾选 Enable Device Flow）"
        default: return "授权失败：\(e)"
        }
    }

    private func requestDeviceCode() -> DeviceCode? {
        let body = "client_id=\(clientID)&scope=\(scope)"
        guard let root = post("https://github.com/login/device/code", body: body),
              let deviceCode = root["device_code"] as? String,
              let userCode = root["user_code"] as? String,
              let verify = root["verification_uri"] as? String else { return nil }
        return DeviceCode(deviceCode: deviceCode, userCode: userCode, verificationURI: verify,
                          interval: (root["interval"] as? Int) ?? 5,
                          expiresIn: (root["expires_in"] as? Int) ?? 900)
    }

    /// → (token, error)。pending / slow_down 时 token 为 nil、error 给出原因。
    private func pollToken(deviceCode: String) -> (String?, String?) {
        let body = "client_id=\(clientID)&device_code=\(deviceCode)"
            + "&grant_type=urn:ietf:params:oauth:grant-type:device_code"
        guard let root = post("https://github.com/login/oauth/access_token", body: body) else { return (nil, nil) }
        if let token = root["access_token"] as? String { return (token, nil) }
        return (nil, root["error"] as? String)
    }

    private func post(_ url: String, body: String) -> [String: Any]? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")   // GitHub 要求带 UA；诚实标识
        req.httpBody = body.data(using: .utf8)

        var out: [String: Any]? = nil
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data = data { out = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 17)
        return out
    }

    // MARK: - 钥匙串（加密存储 gho_ token）

    private func kcQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: kcService,
         kSecAttrAccount as String: kcAccount]
    }
    private func keychainSave(_ token: String) {
        let data = Data(token.utf8)
        let status = SecItemUpdate(kcQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = kcQuery()
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }
    private func keychainLoad() -> String? {
        var q = kcQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(decoding: d, as: UTF8.self)
    }
    private func keychainDelete() { SecItemDelete(kcQuery() as CFDictionary) }
}
