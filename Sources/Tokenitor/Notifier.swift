import Foundation
import AppKit
import UserNotifications

/// 发送系统通知。优先用 UserNotifications（含前台也展示的代理）；
/// 未授权/未打包时回退到 osascript，保证一定能弹。
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private var authorized = false
    private var hasBundle: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard hasBundle else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self   // 关键：让前台时也能展示横幅
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            self.authorized = granted
        }
        // 同步读取一次已有授权状态（用户之前已允许的情况）
        center.getNotificationSettings { s in
            if s.authorizationStatus == .authorized || s.authorizationStatus == .provisional {
                self.authorized = true
            }
        }
    }

    /// App 在前台/聚焦时也展示通知（默认会被抑制）。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func notify(title: String, body: String) {
        // 没有 bundle（极少见）→ 直接兜底
        guard hasBundle else { notifyViaOSAScript(title: title, body: body); return }

        // 关键：发送前「实时」查授权状态，不依赖可能过期的标记。
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                // 原生通知：自动使用 Tokenitor 的 App 图标
                let content = UNMutableNotificationContent()
                content.title = title; content.body = body; content.sound = .default
                let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                center.add(req) { err in
                    if let err = err {
                        log("UN add 失败，回退 osascript: \(err)")
                        self.notifyViaOSAScript(title: title, body: body)
                    } else {
                        log("UN 已投递（原生图标）")
                    }
                }
            case .notDetermined:
                // 还没问过权限：先请求，批了再发（这次就是原生），拒了才兜底
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted {
                        self.authorized = true
                        self.notify(title: title, body: body)   // 重发一次，走原生
                    } else {
                        self.notifyViaOSAScript(title: title, body: body)
                    }
                }
            default:
                // denied → 只能 osascript 兜底（图标会是脚本编辑器）
                log("通知未授权（denied），回退 osascript")
                self.notifyViaOSAScript(title: title, body: body)
            }
        }
    }

    /// 供「测试通知」按钮调用。
    func test() { notify(title: "Tokenitor 测试通知", body: "如果你看到这条，通知就正常了 ✅") }

    private func notifyViaOSAScript(title: String, body: String) {
        let safeTitle = title.replacingOccurrences(of: "\"", with: "'")
        let safeBody = body.replacingOccurrences(of: "\"", with: "'")
        let script = "display notification \"\(safeBody)\" with title \"\(safeTitle)\""
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        do {
            try task.run()
            task.waitUntilExit()
            log("osascript notify exit=\(task.terminationStatus)")
        } catch {
            log("osascript notify error: \(error)")
        }
    }
}

/// 决定何时告警，避免每次刷新都重复弹。
/// 规则：某窗口剩余跌破 warn / crit 阈值时各弹一次；当剩余回升到 warn 之上后重置，可再次触发。
final class AlertEngine {
    /// key -> 已触发的最低档（0=无, 1=warn, 2=crit）
    private var fired: [String: Int] = [:]

    func evaluate(_ snapshots: [ProviderSnapshot]) {
        guard Settings.shared.notificationsEnabled else { return }
        let warn = Settings.shared.warnAt
        let crit = Settings.shared.critAt

        for snap in snapshots where snap.ok {
            for w in snap.windows {
                let key = "\(snap.name)|\(w.label)"
                let remaining = w.remainingPercent
                let prev = fired[key] ?? 0

                if remaining <= crit {
                    if prev < 2 {
                        Notifier.shared.notify(
                            title: "⚠️ \(snap.name) \(w.label) 剩余用量即将耗尽",
                            body: "仅剩 \(Int(remaining))%，\(resetText(w))")
                        fired[key] = 2
                    }
                } else if remaining <= warn {
                    if prev < 1 {
                        Notifier.shared.notify(
                            title: "🟡 \(snap.name) \(w.label) 剩余用量偏低",
                            body: "剩余 \(Int(remaining))%，\(resetText(w))")
                        fired[key] = 1
                    }
                } else {
                    // 恢复，重置
                    fired[key] = 0
                }
            }
        }
    }

    private func resetText(_ w: UsageWindow) -> String {
        let c = formatCountdown(to: w.resetsAt)
        return c.isEmpty ? "暂无重置时间" : "约 \(c) 后重置"
    }
}
