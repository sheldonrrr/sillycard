import SwiftUI

/// 关于 Sillycard
struct AboutSillycardView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image("BrandIcon", bundle: .sillycardResources)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sillycard")
                        .font(.title2.weight(.semibold))
                    Text("本地 PNG 角色卡")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text("为 Silly Tavern 准备的 macOS 角色卡工具：浏览、预览元数据与世界书、编辑并写回 PNG。")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            // 仅营销版本号（CFBundleShortVersionString），不展示 CFBundleVersion。
            Text("版本 \(Bundle.main.sillycardMarketingVersion)")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer(minLength: 8)

            HStack {
                Spacer()
                Button("好") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 360)
    }
}
