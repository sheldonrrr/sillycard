import Foundation

/// 将角色卡 JSON 展平为 Key–Value 行供 Inspector 展示。
enum CharacterCardJSONFlattener {
    static func rows(from jsonString: String, maxDepth: Int = 4, maxValueLength: Int = 800) -> [(String, String)] {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        var out: [(String, String)] = []
        flatten(value: root, prefix: "", depth: 0, maxDepth: maxDepth, maxValueLength: maxValueLength, into: &out)
        return out
    }

    private static func flatten(value: Any, prefix: String, depth: Int, maxDepth: Int, maxValueLength: Int, into out: inout [(String, String)]) {
        if depth > maxDepth {
            if !prefix.isEmpty { out.append((prefix, "…")) }
            return
        }
        switch value {
        case let s as String:
            if !prefix.isEmpty { out.append((prefix, truncate(s, maxValueLength))) }
        case let n as NSNumber:
            if !prefix.isEmpty { out.append((prefix, n.stringValue)) }
        case let b as Bool:
            if !prefix.isEmpty { out.append((prefix, b ? "true" : "false")) }
        case let dict as [String: Any]:
            if dict.isEmpty, !prefix.isEmpty {
                out.append((prefix, "{}"))
                return
            }
            let keys = dict.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            for k in keys {
                guard let v = dict[k] else { continue }
                let next = prefix.isEmpty ? k : "\(prefix).\(k)"
                flatten(value: v, prefix: next, depth: depth + 1, maxDepth: maxDepth, maxValueLength: maxValueLength, into: &out)
            }
        case let arr as [Any]:
            if prefix.isEmpty {
                for (i, v) in arr.enumerated() {
                    flatten(value: v, prefix: "[\(i)]", depth: depth + 1, maxDepth: maxDepth, maxValueLength: maxValueLength, into: &out)
                }
            } else if arr.isEmpty {
                out.append((prefix, "[]"))
            } else if arr.allSatisfy({ $0 is String || $0 is NSNumber || $0 is Bool }) {
                let joined = arr.map { "\($0)" }.joined(separator: ", ")
                out.append((prefix, truncate(joined, maxValueLength)))
            } else {
                out.append((prefix, "[\(arr.count) 项]"))
            }
        default:
            if !prefix.isEmpty {
                out.append((prefix, String(describing: value)))
            }
        }
    }

    private static func truncate(_ s: String, _ max: Int) -> String {
        if s.count <= max { return s }
        return String(s.prefix(max)) + "…"
    }
}
