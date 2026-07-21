import SwiftUI

/// 没有任何可显示的 AI 时的占位：
///  · 首轮抓取还没结束 → 「正在获取用量…」（转圈）
///  · 抓取已结束仍为空 → 明确告诉用户「没检测到在用的 AI」并给出下一步怎么做，
///    而不是让「正在获取用量…」一直转下去（那会让人以为程序卡住了）。
struct EmptyStateView: View {
    let hasFetched: Bool
    var compact: Bool = false
    var onOpenSettings: () -> Void

    var body: some View {
        if !hasFetched {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("正在获取用量…", "Fetching usage…"))
                    .font(compact ? .uiCaption : .uiBody)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                Label(L("未检测到正在使用的 AI", "No active AI tools detected"),
                      systemImage: "questionmark.circle")
                    .font(compact ? .uiCaption : .sectionTitle)
                    .foregroundStyle(.primary)
                Text(L("· Codex / Gemini：在本机用过一次即自动出现（读取本地会话文件）\n· Claude / Copilot：默认关闭，需在设置里启用并授权一次",
                       "· Codex / Gemini: appear automatically once used on this Mac (read from local session files)\n· Claude / Copilot: off by default — enable and authorize once in Settings"))
                    .font(.uiCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("打开设置", "Open Settings"), action: onOpenSettings)
                    .controlSize(compact ? .small : .regular)
                    .padding(.top, 2)
            }
            .padding(compact ? 10 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: compact ? 12 : 16)
        }
    }
}
