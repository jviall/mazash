import Foundation

enum SpotifyConfig {
    static let clientId: String   = Bundle.main.infoDictionary?["SpotifyClientId"]   as? String ?? ""
    static let playlistId: String = Bundle.main.infoDictionary?["SpotifyPlaylistId"] as? String ?? ""

    /// True only when both credentials are present; gates all Spotify UI and behaviour.
    static var isConfigured: Bool { !clientId.isEmpty && !playlistId.isEmpty }
}
