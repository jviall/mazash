import Foundation
import ShazamKit

struct Match {
    let timestamp: Date
    let mediaItem: SHMediaItem

    var title: String { mediaItem.title ?? "Unknown Title" }
    var artist: String { mediaItem.artist ?? "Unknown Artist" }

    var formattedLine: String {
        Match.formatLine(title: title, artist: artist, date: timestamp)
    }

    // Uses local time (TimeZone.current) intentionally — matches are displayed in the user's timezone.
    private static let lineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func formatLine(title: String, artist: String, date: Date) -> String {
        "\(lineFormatter.string(from: date)) | \(title) - \(artist)"
    }
}
