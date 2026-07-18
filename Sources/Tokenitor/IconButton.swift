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

/// 弹层可靠版 hover 跟踪：菜单栏弹层常在 **app 未激活** 时打开，SwiftUI `.onHover` 的默认
/// tracking（activeInKeyWindow）此时会迟钝、丢失进出事件——表现为高亮跟不上鼠标。
/// 换成 NSTrackingArea(.activeAlways)：无论窗口激活与否都即时回调。
struct ActiveHoverView: NSViewRepresentable {
    let onChange: (Bool) -> Void
    func makeNSView(context: Context) -> HoverNSView { HoverNSView(onChange: onChange) }
    func updateNSView(_ v: HoverNSView, context: Context) { v.onChange = onChange }

    final class HoverNSView: NSView {
        var onChange: (Bool) -> Void
        init(onChange: @escaping (Bool) -> Void) { self.onChange = onChange; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil))
        }
        override func mouseEntered(with event: NSEvent) { onChange(true) }
        override func mouseExited(with event: NSEvent) { onChange(false) }
    }
}

extension View {
    /// `.onHover` 的弹层可靠版（窗口未激活也即时响应）。
    func activeHover(_ onChange: @escaping (Bool) -> Void) -> some View {
        background(ActiveHoverView(onChange: onChange))
    }
}
