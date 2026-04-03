import Foundation

/// 将角色卡内嵌 JSON 排版为多行并排序键名，便于在编辑窗口中浏览结构。
enum CharacterCardJSONPretty {
    static func format(_ jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return jsonString }
        guard let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: out, encoding: .utf8)
        else { return jsonString }
        return s
    }

    static func isValidJSONString(_ jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    /// 单行紧凑 JSON（键排序），用于复制「无换行」的合法源码。
    static func minified(_ jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        guard let out = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let s = String(data: out, encoding: .utf8)
        else { return nil }
        return s
    }
}
