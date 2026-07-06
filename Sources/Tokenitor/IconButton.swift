import SwiftUI

/// 方形图标按钮：常态有淡背景块，悬停时背景明显加深（hover 反馈），并显示手型光标。
struct IconButton: View {
    let systemName: String
    let help: String
    var prominent: Bool = false      // 主操作（如刷新）用强调色
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(prominent ? 0 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .help(help)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var background: Color {
        if prominent { return Color.accentColor.opacity(hovering ? 0.85 : 1.0) }
        return Color.primary.opacity(hovering ? 0.16 : 0.06)
    }
}

/// 统一悬停反馈：轻微放大 + 提亮 + 手型光标。
/// 用于所有自定义可点控件（社交按钮、设置页动作按钮、分段控件等），与 IconButton 手感一致。
struct PressableHover: ViewModifier {
    @State private var hovering = false
    var scale: CGFloat = 1.03

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .brightness(hovering ? 0.04 : 0)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { h in
                hovering = h
                if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
    }
}

extension View {
    /// 悬停反馈（放大 + 提亮 + 手型光标）。
    func pressableHover(scale: CGFloat = 1.03) -> some View { modifier(PressableHover(scale: scale)) }
}
