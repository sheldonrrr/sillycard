import Foundation

extension Bundle {
    /// SwiftPM：`SillycardKit` 目标下为 `.module`；Xcode 单应用目标下资源在主 Bundle，用 `.main`。
    static var sillycardResources: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }

    /// 面向用户的短版本号（`CFBundleShortVersionString`），缺省为 `1.0`。
    var sillycardMarketingVersion: String {
        let s = (infoDictionary?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? "1.0" : s
    }
}
