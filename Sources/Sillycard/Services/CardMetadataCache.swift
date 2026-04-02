import Foundation

/// Parsed JSON + bookkeeping for Sillycard metadata cache (see plan: lastReadAt, mtime).
struct CachedCardMetadata: Sendable, Equatable {
    var jsonString: String
    /// Last time metadata was loaded from disk PNG, refreshed, or saved and written to cache.
    var lastReadAt: Date
    var sourceFileMTime: Date?
}
