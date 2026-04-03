import Foundation

/// 从角色卡 JSON 解析 Silly Tavern 主界面常用字段与世界书条目，用于右侧预览排版。
struct SillyTavernCardPreview {
    struct WorldBookEntryPreview: Identifiable {
        let id: String
        /// 展示用标题（name / comment / 序号）
        let title: String
        let keysPrimary: String
        let keysSecondary: String
        let content: String
        let order: Int?
        let priority: Int?
        let selective: Bool?
        let constant: Bool?
        let disabled: Bool?
    }

    let name: String?
    let tags: [String]
    let description: String?
    let personality: String?
    let scenario: String?
    let firstMes: String?
    let mesExample: String?
    let creatorNotes: String?
    let systemPrompt: String?
    let postHistoryInstructions: String?
    let creator: String?
    let characterVersion: String?
    let alternateGreetings: [String]

    let hasEmbeddedWorldBook: Bool
    let worldBookName: String?
    let worldBookEntries: [WorldBookEntryPreview]

    init(jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            name = nil
            tags = []
            description = nil
            personality = nil
            scenario = nil
            firstMes = nil
            mesExample = nil
            creatorNotes = nil
            systemPrompt = nil
            postHistoryInstructions = nil
            creator = nil
            characterVersion = nil
            alternateGreetings = []
            hasEmbeddedWorldBook = false
            worldBookName = nil
            worldBookEntries = []
            return
        }

        let dataObj = (root["data"] as? [String: Any]) ?? root

        name = Self.string(from: dataObj["name"])
        tags = Self.stringArray(from: dataObj["tags"])
        description = Self.string(from: dataObj["description"])
        personality = Self.string(from: dataObj["personality"])
        scenario = Self.string(from: dataObj["scenario"])
        firstMes = Self.string(from: dataObj["first_mes"])
        mesExample = Self.string(from: dataObj["mes_example"])
        creatorNotes = Self.string(from: dataObj["creator_notes"])
        systemPrompt = Self.string(from: dataObj["system_prompt"])
        postHistoryInstructions = Self.string(from: dataObj["post_history_instructions"])
        creator = Self.string(from: dataObj["creator"])
        characterVersion = Self.string(from: dataObj["character_version"])

        if let alts = dataObj["alternate_greetings"] as? [String] {
            alternateGreetings = alts
        } else {
            alternateGreetings = []
        }

        let (hasBook, bookName, entries) = Self.extractWorldBook(from: dataObj, root: root)
        hasEmbeddedWorldBook = hasBook
        worldBookName = bookName
        worldBookEntries = entries
    }

    private static func extractWorldBook(from dataObj: [String: Any], root: [String: Any]) -> (Bool, String?, [WorldBookEntryPreview]) {
        let bookDict = (dataObj["character_book"] as? [String: Any])
            ?? (root["character_book"] as? [String: Any])

        guard let book = bookDict,
              let rawEntries = book["entries"] as? [Any],
              !rawEntries.isEmpty
        else {
            return (false, nil, [])
        }

        let bookName = string(from: book["name"])
        var out: [WorldBookEntryPreview] = []
        for (idx, el) in rawEntries.enumerated() {
            guard let e = el as? [String: Any] else { continue }
            let title = string(from: e["name"]).nonEmpty
                ?? string(from: e["comment"]).nonEmpty
                ?? "条目 \(idx + 1)"

            let keysP = joinKeys(e["keys"] ?? e["key"])
            let keysS = joinKeys(e["secondary_keys"] ?? e["keysecondary"])
            let content = string(from: e["content"]) ?? ""
            let order = int(from: e["order"] ?? e["position"])
            let priority = int(from: e["priority"])
            let selective = e["selective"] as? Bool
            let constant = (e["constant"] as? Bool) ?? (e["constant"] as? NSNumber)?.boolValue
            let disabled: Bool? = {
                if let d = e["disable"] as? Bool { return d }
                if let en = e["enabled"] as? Bool { return !en }
                return nil
            }()

            let uid = string(from: e["uid"]) ?? "\(idx)-\(title.hashValue)"
            out.append(WorldBookEntryPreview(
                id: uid,
                title: title,
                keysPrimary: keysP,
                keysSecondary: keysS,
                content: content,
                order: order,
                priority: priority,
                selective: selective,
                constant: constant,
                disabled: disabled
            ))
        }
        return (!out.isEmpty, bookName, out)
    }

    private static func joinKeys(_ any: Any?) -> String {
        if let arr = any as? [String] {
            return arr
                .map { CharacterCardPreviewFormatting.normalizeDisplayEscapes($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
        if let s = any as? String { return CharacterCardPreviewFormatting.normalizeDisplayEscapes(s) }
        return ""
    }

    private static func string(from any: Any?) -> String? {
        if let s = any as? String { return CharacterCardPreviewFormatting.normalizeDisplayEscapes(s) }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private static func stringArray(from any: Any?) -> [String] {
        if let arr = any as? [String] {
            return arr.map { CharacterCardPreviewFormatting.normalizeDisplayEscapes($0) }
        }
        if let s = any as? String, !s.isEmpty { return [CharacterCardPreviewFormatting.normalizeDisplayEscapes(s)] }
        return []
    }

    private static func int(from any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let s = self, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }
}
