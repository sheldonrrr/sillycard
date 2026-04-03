import AppKit
import Foundation
import SwiftUI

/// 首次启动欢迎；已从菜单打开时不改写版本记录逻辑（由 `ContentView` 处理）。
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    var onReleaseNotes: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SampleCardBannerView(height: 124)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("欢迎使用 Sillycard")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 14) {
                bullet(title: "角色卡库", detail: "本地集中保存 PNG 角色卡，多卡库与归档。首次打开附示例卡 Meo。")
                bullet(title: "预览与编辑", detail: "侧栏对标 Silly Tavern 常用字段与嵌入世界书；可进独立窗口改 JSON。")
                bullet(title: "标签与视图", detail: "标签交集筛选；默认库可选网格或列表。")
            }

            Spacer(minLength: 8)

            HStack {
                Button("当前版本介绍") { onReleaseNotes() }
                Spacer()
                Button("开始") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(minWidth: 460, minHeight: 400, idealHeight: 500, maxHeight: 620)
    }

    private func bullet(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tertiary)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 使用打包的 `cat_banner.png`（若无则从 Meo 卡裁切）作横向 banner；欢迎 / 关于 / 版本说明共用。
struct SampleCardBannerView: View {
    var height: CGFloat = 116

    var body: some View {
        Group {
            if let ns = BundledSampleCard.welcomeBannerNSImage() {
                Image(nsImage: ns)
                    .resizable()
                    .scaledToFill()
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(height: max(72, height * 0.55))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

// MARK: - 内置 Meo 示例（与 `WelcomeView` 同文件，避免 Xcode 工程未收录 `BundledSampleCard.swift` 时符号缺失；`LibraryViewModel` 仍可直接调用）
enum BundledSampleCard {
    static let pngFileName = "Meo"
    static let pngExtension = "png"

    static func resourceURL() -> URL? {
        Bundle.sillycardResources.url(forResource: pngFileName, withExtension: pngExtension)
    }

    /// 欢迎 / 关于等界面优先使用专用 banner 资源；仅 SwiftPM / Xcode 把 `Resources` 复制进包后可见。
    static func welcomeBannerNSImage() -> NSImage? {
        if let url = Bundle.sillycardResources.url(forResource: "cat_banner", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return meoCroppedBannerNSImage()
    }

    private static func meoCroppedBannerNSImage() -> NSImage? {
        guard let url = resourceURL(),
              let img = NSImage(contentsOf: url),
              let rep = img.bestBitmapRep(),
              let cg = rep.cgImage
        else { return nil }
        let w = CGFloat(rep.pixelsWide)
        let h = CGFloat(rep.pixelsHigh)
        guard w > 2, h > 2 else { return img }
        let cropH = max(80, h * 0.42)
        let cropY = max(0, h * 0.08)
        let rect = CGRect(x: 0, y: cropY, width: w, height: min(cropH, h - cropY))
        guard let cropped = cg.cropping(to: rect) else { return img }
        return NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
    }

    static func seedIntoEmptyManagedLibrary(root: URL) {
        guard let src = resourceURL() else { return }
        let dest = root.appendingPathComponent("\(pngFileName).\(pngExtension)")
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        do {
            let n = try LibraryScanner.scan(root: root).count
            guard n == 0 else { return }
            try FileManager.default.copyItem(at: src, to: dest)
            var dates = [FileAttributeKey: Any]()
            dates[.modificationDate] = Date()
            try FileManager.default.setAttributes(dates, ofItemAtPath: dest.path)
        } catch {}
    }
}

private extension NSImage {
    func bestBitmapRep() -> NSBitmapImageRep? {
        for rep in representations {
            if let b = rep as? NSBitmapImageRep { return b }
        }
        guard let data = tiffRepresentation,
              let rep = NSBitmapImageRep(data: data)
        else { return nil }
        return rep
    }
}
