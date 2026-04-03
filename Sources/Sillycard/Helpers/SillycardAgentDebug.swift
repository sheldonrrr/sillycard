import Foundation

/// Debug ingest：NDJSON 追加到 `.cursor/debug-f14567.log`（会话 f14567）。
enum SillycardAgentDebug {
    private static let logPath = "/Users/sheldon/sillycard/.cursor/debug-f14567.log"

    // #region agent log
    static func log(hypothesisId: String, location: String, message: String, data: [String: String] = [:]) {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        var obj: [String: Any] = [
            "sessionId": "f14567",
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "timestamp": ts,
        ]
        if !data.isEmpty { obj["data"] = data }
        guard let json = try? JSONSerialization.data(withJSONObject: obj),
              var line = String(data: json, encoding: .utf8)
        else { return }
        line.append("\n")
        guard let bytes = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: logPath)
        if FileManager.default.fileExists(atPath: logPath) {
            if let h = try? FileHandle(forWritingTo: url) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: bytes)
            }
        } else {
            try? bytes.write(to: url, options: .atomic)
        }
    }
    // #endregion
}
