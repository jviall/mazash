import Foundation

struct Match {
    let timestamp: Date
    let title: String
    let artist: String
    let spotifyTrackId: String?
    let youtubeVideoId: String?

    init(timestamp: Date, title: String, artist: String,
         spotifyTrackId: String? = nil, youtubeVideoId: String? = nil) {
        self.timestamp = timestamp
        self.title = title
        self.artist = artist
        self.spotifyTrackId = spotifyTrackId
        self.youtubeVideoId = youtubeVideoId
    }

    var formattedLine: String {
        var parts = ["\(Self.lineFormatter.string(from: timestamp)) | \(title) - \(artist)"]
        if let id = spotifyTrackId  { parts.append("spotify:\(id)") }
        if let id = youtubeVideoId  { parts.append("youtube:\(id)") }
        return parts.joined(separator: " | ")
    }

    // Uses local time (TimeZone.current) intentionally — matches are displayed in the user's timezone.
    private static let lineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
