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

    static func formatLine(title: String, artist: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "\(formatter.string(from: date)) | \(title) - \(artist)"
    }
}
