import AppKit
import CryptoKit
import Foundation
import Security

// All methods run on the main actor; URLSession suspensions don't block it.
@Observable
@MainActor
final class SpotifyService {

    enum AuthState { case disconnected, authenticating, connected }

    private(set) var authState: AuthState = .disconnected
    private(set) var userName: String?

    private let clientId: String
    private let playlistId: String

    // Ephemeral — only valid during an in-flight OAuth handshake.
    private var pendingVerifier: String?
    private var pendingOAuthState: String?

    // MARK: - Init

    init(clientId: String, playlistId: String) {
        self.clientId = clientId
        self.playlistId = playlistId
        if loadToken(key: .accessToken) != nil {
            authState = .connected
            Task { await fetchDisplayName() }
        }
    }

    // MARK: - Public interface

    func connect() {
        let verifier = makeVerifier()
        let challenge = makeChallenge(from: verifier)
        let state = UUID().uuidString
        pendingVerifier = verifier
        pendingOAuthState = state
        authState = .authenticating

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id",             value: clientId),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "redirect_uri",          value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "scope",                 value: "playlist-modify-public playlist-modify-private"),
            URLQueryItem(name: "state",                 value: state),
        ]
        NSWorkspace.shared.open(components.url!)
    }

    func handleCallback(url: URL) {
        guard url.scheme == "mazash", url.host == "spotify",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let code  = items.first(where: { $0.name == "code" })?.value,
              let state = items.first(where: { $0.name == "state" })?.value,
              state == pendingOAuthState,
              let verifier = pendingVerifier else {
            // macOS may deliver the callback URL more than once; ignore duplicates silently.
            if authState == .authenticating {
                print("[Spotify] callback URL invalid or state mismatch — aborting auth")
                authState = .disconnected
            }
            return
        }
        pendingVerifier = nil
        pendingOAuthState = nil
        Task { await exchangeCode(code, verifier: verifier) }
    }

    func disconnect() {
        deleteTokens()
        authState = .disconnected
        userName = nil
    }

    /// Adds the track to the configured playlist, silently skipping known duplicates.
    func addTrack(spotifyId: String, label: String) async {
        guard !isDuplicate(spotifyId) else {
            print("[Spotify] duplicate, skipping \"\(label)\"")
            return
        }
        guard let token = await validToken() else {
            print("[Spotify] no valid token — cannot add track")
            return
        }

        let url = URL(string: "https://api.spotify.com/v1/playlists/\(playlistId)/tracks")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["uris": ["spotify:track:\(spotifyId)"]])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 201 {
                markAdded(spotifyId)
                print("[Spotify] added \"\(label)\" to playlist")
            } else {
                let body = String(data: data, encoding: .utf8) ?? "<unreadable>"
                print("[Spotify] add failed (\((response as? HTTPURLResponse)?.statusCode ?? -1)): \(body)")
            }
        } catch {
            print("[Spotify] add error: \(error)")
        }
    }

    // MARK: - Duplicate tracking

    private static let addedKey = "spotify_added_track_ids"

    private func isDuplicate(_ id: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: Self.addedKey) ?? []).contains(id)
    }

    private func markAdded(_ id: String) {
        var ids = UserDefaults.standard.stringArray(forKey: Self.addedKey) ?? []
        ids.append(id)
        UserDefaults.standard.set(ids, forKey: Self.addedKey)
    }

    // MARK: - Token management

    private func fetchDisplayName() async {
        guard let token = await validToken() else { return }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        struct Me: Decodable { let display_name: String? }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let me = try? JSONDecoder().decode(Me.self, from: data) else { return }
        userName = me.display_name
    }

    private func validToken() async -> String? {
        let expiry = UserDefaults.standard.double(forKey: TokenKey.expiry.rawValue)
        // Refresh 60 s before expiry to avoid edge-race.
        if expiry > Date().timeIntervalSince1970 + 60, let t = loadToken(key: .accessToken) {
            return t
        }
        return await refreshToken()
    }

    private func refreshToken() async -> String? {
        guard let refresh = loadToken(key: .refreshToken) else { return nil }
        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refresh)",
            "client_id=\(clientId)",
        ].joined(separator: "&")
        return await exchangeTokens(body: body)
    }

    private func exchangeCode(_ code: String, verifier: String) async {
        let body = [
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(redirectURI)",
            "client_id=\(clientId)",
            "code_verifier=\(verifier)",
        ].joined(separator: "&")
        if await exchangeTokens(body: body) != nil {
            authState = .connected
            await fetchDisplayName()
        } else {
            authState = .disconnected
        }
    }

    /// Posts to the token endpoint, stores the result, and returns the access token on success.
    @discardableResult
    private func exchangeTokens(body: String) async -> String? {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)

        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
            let scope: String?
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let r = try JSONDecoder().decode(TokenResponse.self, from: data)
            saveToken(r.access_token, key: .accessToken)
            if let refresh = r.refresh_token { saveToken(refresh, key: .refreshToken) }
            let expiry = Date().timeIntervalSince1970 + Double(r.expires_in)
            UserDefaults.standard.set(expiry, forKey: TokenKey.expiry.rawValue)
            return r.access_token
        } catch {
            print("[Spotify] token exchange failed: \(error)")
            return nil
        }
    }

    // MARK: - Keychain

    private enum TokenKey: String {
        case accessToken  = "spotify_access_token"
        case refreshToken = "spotify_refresh_token"
        case expiry       = "spotify_token_expiry"
    }

    private static let keychainService = "com.local.mazash.spotify"

    private func saveToken(_ token: String, key: TokenKey) {
        let data = Data(token.utf8)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    private func loadToken(key: TokenKey) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: key.rawValue,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteTokens() {
        for key in [TokenKey.accessToken, .refreshToken] {
            let query: [CFString: Any] = [
                kSecClass:       kSecClassGenericPassword,
                kSecAttrService: Self.keychainService,
                kSecAttrAccount: key.rawValue,
            ]
            SecItemDelete(query as CFDictionary)
        }
        UserDefaults.standard.removeObject(forKey: TokenKey.expiry.rawValue)
    }

    // MARK: - PKCE helpers

    private let redirectURI = "mazash://spotify"

    private func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(
            Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
                .prefix(128)
        )
    }

    private func makeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

