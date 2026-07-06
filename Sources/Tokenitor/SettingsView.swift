import SwiftUI

/// 主窗口内的「设置页」：左上角返回 + 标题 + 设置内容。与用量页在同一个窗口里切换。
struct SettingsView: View {
    @ObservedObject var store: UsageStore
    var inPopover: Bool = false   // 主窗口头部由自绘 header 提供（见 DashboardView.mainHeaderRow），弹层才画自己的头

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if inPopover {
                HStack(spacing: 10) {
                    IconButton(systemName: "chevron.left", help: L("返回", "Back")) { store.page = .usage }
                    Text(L("设置", "Settings")).font(.pageTitle)
                    Spacer()
                }
            }
            SettingsPanelView(store: store)
        }
    }
}
