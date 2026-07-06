import SwiftUI

/// SwiftUI 展示层的数据源：AppDelegate 每次刷新写入 snapshots，视图自动重绘。
/// 同时承载几个动作回调（刷新/说明/测试通知/设置变更），由 AppDelegate 注入。
/// 主窗口内的页面：用量 / Token / 设置（同窗口切换）。
enum AppPage { case usage, tokens, tokenInfo, language, appearance, settings, about, help }

final class UsageStore: ObservableObject {
    @Published var snapshots: [ProviderSnapshot] = []
    @Published var lastUpdate: Date? = nil
    @Published var page: AppPage = .usage    // 主窗口内页面切换

    // Token 页数据
    @Published var tokenStats: [TokenStat] = []
    @Published var tokensUpdate: Date? = nil

    // 厂商服务状态（AI 名 → statuspage indicator），由 StatusMonitor 每 5 分钟更新
    @Published var serviceStatus: [String: String] = [:]

    // 主窗口：用户是否已手动拖动过窗口。true 后内容改为「填充窗口宽 + 顶对齐」，不再自动贴合高度。
    @Published var fillHeight = false

    var onRefresh: () -> Void = {}
    var onShowHelp: () -> Void = {}
    var onShowSettings: () -> Void = {}
    var onTestNotify: () -> Void = {}
    var onSettingsChanged: () -> Void = {}
    var onReloginClaude: () -> Void = {}
    var onLoginCopilot: () -> Void = {}   // Copilot device flow 授权
    // 弹窗（速览）里点 Token/设置 → 打开完整主窗口并跳到该页
    var onOpenWindow: (AppPage) -> Void = { _ in }
    // 窗口自适应：内容高度变化时回调，AppDelegate 据此调整窗口高度
    var onMainHeight: (CGFloat) -> Void = { _ in }

    /// 在主线程更新数据（网络刷新后调用，会刷新「更新于」时间）
    func update(_ snaps: [ProviderSnapshot]) {
        snapshots = snaps
        lastUpdate = Date()
    }

    /// 仅替换快照、不改「更新于」时间。用于设置变更后的瞬时增删（如关掉某个 AI 立即隐藏）。
    func setSnapshots(_ snaps: [ProviderSnapshot]) {
        snapshots = snaps
    }

    /// 更新 Token 页数据。
    func updateTokens(_ stats: [TokenStat]) {
        tokenStats = stats
        tokensUpdate = Date()
    }
}
