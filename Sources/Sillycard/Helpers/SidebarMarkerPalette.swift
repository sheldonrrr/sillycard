import SwiftUI

/// 侧栏卡库（菱形）与标签（圆形）的稳定配色，便于快速区分。
enum SidebarMarkerPalette {
    enum Variant {
        case library
        case tag
    }

    static func color(forKey key: String, variant: Variant) -> Color {
        var hash: UInt64 = 1469598103934665603
        for b in key.utf8 {
            hash ^= UInt64(b)
            hash &*= 1099511628211
        }
        let t = Double(hash % 1000) / 1000.0
        switch variant {
        case .library:
            // 稿中卡库菱形偏紫粉，在同色系内随 id 微调。
            let hue = 0.72 + t * 0.08
            return Color(hue: hue, saturation: 0.42, brightness: 0.88)
        case .tag:
            // 稿中标签圆点为浅蓝系。
            let hue = 0.54 + t * 0.12
            return Color(hue: hue, saturation: 0.45, brightness: 0.90)
        }
    }
}

/// 卡库行左侧菱形标记（10×10 pt）。
struct LibraryDiamondMarker: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: 10, height: 10)
            .rotationEffect(.degrees(45))
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
    }
}

/// 标签行左侧圆点标记。
struct TagCircleMarker: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}
