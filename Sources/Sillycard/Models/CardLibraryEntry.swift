import Foundation

/// 一个「卡库」：应用内托管目录，或通过书签指向的外部文件夹。
struct CardLibraryEntry: Codable, Identifiable, Hashable {
    let id: String
    var displayName: String
    /// 非空时表示用户附加的外部资料夹（安全作用域书签）。
    var bookmarkData: Data?

    var isManaged: Bool { bookmarkData == nil }
}

struct CardLibraryManifest: Codable {
    var libraries: [CardLibraryEntry]
    var activeLibraryId: String?
}
