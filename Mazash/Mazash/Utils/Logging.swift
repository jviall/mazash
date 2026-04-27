import Foundation

// MARK: - Formatters

enum Formatters {
    /// `yyyy-MM-dd` — daily file names.
    static let fileDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// `yyyy-MM-dd HH:mm:ss` — file content: match lines and session markers.
    // Uses TimeZone.current intentionally — matches are shown in the user's local time.
    static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SS"
        return f
    }()
}

// MARK: - Logging

/// Prints a timestamped log line, e.g. `[14:23:01] [Spotify] added "Song" to playlist`.
func log(_ message: String) {
    print("[\(Formatters.timestamp.string(from: Date()))] \(message)")
}
