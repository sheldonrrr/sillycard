import Foundation

/// 按展平路径（与 `CharacterCardJSONFlattener` 一致）读写字典 / 数组中的叶节点。
enum CharacterCardJSONPathMutation {
    enum PathSegment: Equatable {
        case key(String)
        case index(Int)
    }

    enum MutationError: LocalizedError {
        case invalidJSON
        case invalidPath(String)
        case pathNotFound
        case typeMismatch

        var errorDescription: String? {
            switch self {
            case .invalidJSON: "无法解析 JSON"
            case .invalidPath(let s): "无效路径：\(s)"
            case .pathNotFound: "路径不存在"
            case .typeMismatch: "类型与 JSON 中原值不兼容"
            }
        }
    }

    static func parsePath(_ path: String) throws -> [PathSegment] {
        if path.isEmpty { throw MutationError.invalidPath(path) }
        var segments: [PathSegment] = []
        var i = path.startIndex
        var keyBuf = ""
        func flushKey() {
            if !keyBuf.isEmpty {
                segments.append(.key(keyBuf))
                keyBuf = ""
            }
        }
        while i < path.endIndex {
            let c = path[i]
            if c == "." {
                flushKey()
                i = path.index(after: i)
            } else if c == "[" {
                flushKey()
                let after = path.index(after: i)
                guard let end = path[after...].firstIndex(of: "]") else {
                    throw MutationError.invalidPath(path)
                }
                let inner = String(path[after..<end])
                guard let idx = Int(inner) else { throw MutationError.invalidPath(path) }
                segments.append(.index(idx))
                i = path.index(after: end)
            } else {
                keyBuf.append(c)
                i = path.index(after: i)
            }
        }
        flushKey()
        guard !segments.isEmpty else { throw MutationError.invalidPath(path) }
        return segments
    }

    static func getLeaf(jsonString: String, path: String) throws -> Any? {
        let root = try jsonObject(from: jsonString)
        return try walk(root: root, segments: try parsePath(path))
    }

    /// 将叶节点设为从字符串推断的类型（尽量沿用原值类型）。
    static func setLeafString(jsonString: String, path: String, newValue: String) throws -> String {
        var root = try jsonObject(from: jsonString)
        let segs = try parsePath(path)
        let oldLeaf = try walk(root: root, segments: segs)
        let coerced = coerceLeaf(from: newValue, previous: oldLeaf)
        try setLeaf(in: &root, segments: segs, value: coerced)
        return try serializeCompact(root)
    }

    private static func jsonObject(from jsonString: String) throws -> Any {
        guard let data = jsonString.data(using: .utf8) else { throw MutationError.invalidJSON }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func serializeCompact(_ root: Any) throws -> String {
        guard JSONSerialization.isValidJSONObject(root) else { throw MutationError.invalidJSON }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        guard let s = String(data: data, encoding: .utf8) else { throw MutationError.invalidJSON }
        return s
    }

    private static func walk(root: Any, segments: [PathSegment]) throws -> Any {
        var cur: Any = root
        for seg in segments {
            switch seg {
            case .key(let k):
                guard let d = cur as? [String: Any], let next = d[k] else { throw MutationError.pathNotFound }
                cur = next
            case .index(let idx):
                guard let a = cur as? [Any], idx >= 0, idx < a.count else { throw MutationError.pathNotFound }
                cur = a[idx]
            }
        }
        return cur
    }

    private static func setLeaf(in root: inout Any, segments: [PathSegment], value: Any) throws {
        guard !segments.isEmpty else { throw MutationError.invalidPath("") }
        if segments.count == 1 {
            switch segments[0] {
            case .key(let k):
                guard var d = root as? [String: Any] else { throw MutationError.typeMismatch }
                d[k] = value
                root = d
            case .index(let idx):
                guard var a = root as? [Any], idx >= 0, idx < a.count else { throw MutationError.pathNotFound }
                a[idx] = value
                root = a
            }
            return
        }

        switch segments[0] {
        case .key(let k):
            guard var d = root as? [String: Any], var child = d[k] else { throw MutationError.pathNotFound }
            try setLeaf(in: &child, segments: Array(segments.dropFirst()), value: value)
            d[k] = child
            root = d
        case .index(let idx):
            guard var a = root as? [Any], idx >= 0, idx < a.count else { throw MutationError.pathNotFound }
            var child = a[idx]
            try setLeaf(in: &child, segments: Array(segments.dropFirst()), value: value)
            a[idx] = child
            root = a
        }
    }

    private static func coerceLeaf(from text: String, previous: Any?) -> Any {
        if let prev = previous {
            switch prev {
            case let s as String:
                return s == text ? s : text
            case let b as Bool:
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if t == "true" || t == "1" { return true }
                if t == "false" || t == "0" || t == "no" { return false }
                return b
            case let n as NSNumber:
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let i = Int(t) { return NSNumber(value: i) }
                if let d = Double(t) { return NSNumber(value: d) }
                return n
            default:
                break
            }
        }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t == "true" { return true }
        if t == "false" { return false }
        if let i = Int(t) { return i }
        if let d = Double(t) { return d }
        return text
    }
}

// MARK: - 可编辑行判定（与 flattener 摘要值对齐）

extension CharacterCardJSONPathMutation {
    /// 呈「[n 项]」「…」等摘要的路径不可当作文本叶节点编辑。
    static func isEditableFlattenedValue(path: String, displayValue: String) -> Bool {
        let v = displayValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if v == "…" || v == "{}" || v == "[]" { return false }
        if v.range(of: #"^\[[0-9]+ 项\]$"#, options: .regularExpression) != nil { return false }
        return true
    }
}

