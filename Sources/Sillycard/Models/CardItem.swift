import Foundation

struct CardItem: Identifiable, Hashable {
    var id: URL { fileURL }
    let fileURL: URL
    let relativeFolder: String

    var displayName: String {
        fileURL.deletingPathExtension().lastPathComponent
    }
}

enum CardParseState: Equatable {
    case unknown
    case ok
    case noMetadata
    case error(String)
}
