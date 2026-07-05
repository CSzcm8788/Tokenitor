import SwiftUI
import AppKit

/// 把 NSVisualEffectView 包进 SwiftUI，用作窗口的半透明底。
/// behindWindow 模式会把桌面/下层内容模糊透进来——这样上层的 Liquid Glass 卡片
/// 才有「底」可以折射，玻璃质感才明显（否则叠在纯深色上会显得很平）。
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}
