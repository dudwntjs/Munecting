import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

@MainActor
final class SpotifyLibraryService: NSObject {
    private enum Configuration {
        static let clientID = "c7a8e00cc75c4ccaafabc735603a1ab6"
        static let redirectURI = "munecting-spotify-login://callback"
        static let callbackScheme = "munecting-spotify-login"
        static let scopes = "playlist-read-private playlist-read-collaborative playlist-modify-private"
    }

    private var authenticationSession: ASWebAuthenticationSession?
    private var accessToken: String?
    private var expiresAt: Date = .distantPast
    private let keychain = SpotifyTokenStore()

    func playlists() async throws -> [SharedPlaylist] {
        let token = try await validAccessToken()
        let summaries: [PlaylistSummary] = try await fetchPages(
            path: "/v1/me/playlists",
            token: token
        )

        var result: [SharedPlaylist] = []
        for summary in summaries {
            let tracks: [PlaylistItem] = try await fetchPages(
                path: "/v1/playlists/\(summary.id)/tracks",
                token: token,
                queryItems: [URLQueryItem(name: "fields", value: "items(item(id,name,duration_ms,external_urls,artists(name),album(name,images),external_ids)),next,total")]
            )
            result.append(map(summary, items: tracks))
        }
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func disconnect() {
        accessToken = nil
        expiresAt = .distantPast
        keychain.deleteRefreshToken()
    }

    func createPlaylist(from playlist: SharedPlaylist) async throws -> PlaylistExportResult {
        guard !playlist.tracks.isEmpty else { throw PlaylistExportError.emptyPlaylist }
        let token = try await validAccessToken()
        var matchedURIs: [String] = []
        var unmatched: [MusicTrack] = []

        for track in playlist.tracks {
            if let uri = try await matchURI(for: track, token: token) { matchedURIs.append(uri) }
            else { unmatched.append(track) }
        }
        guard !matchedURIs.isEmpty else { throw PlaylistExportError.noTracksMatched }

        let created: CreatedPlaylist = try await sendJSON(
            path: "/v1/me/playlists", method: "POST", token: token,
            body: ["name": playlist.title, "description": playlist.message ?? "Munecting에서 받은 믹스", "public": false]
        )
        for start in stride(from: 0, to: matchedURIs.count, by: 100) {
            let end = min(start + 100, matchedURIs.count)
            try await sendWithoutResponse(
                path: "/v1/playlists/\(created.id)/items", method: "POST", token: token,
                body: ["uris": Array(matchedURIs[start..<end])]
            )
        }
        guard let url = URL(string: created.externalURLs.spotify) else { throw SpotifyError.invalidCallback }
        return PlaylistExportResult(url: url, matchedCount: matchedURIs.count, unmatchedTracks: unmatched)
    }

    func spotifyURI(for track: MusicTrack) async throws -> String? {
        let token = try await validAccessToken()
        return try await matchedTrack(for: track, token: token)?.uri
    }

    func artworkURL(for track: MusicTrack) async throws -> URL? {
        let token = try await validAccessToken()
        return try await matchedTrack(for: track, token: token)?.album?.images?.first?.url
    }

    private func matchURI(for track: MusicTrack, token: String) async throws -> String? {
        try await matchedTrack(for: track, token: token)?.uri
    }

    private func matchedTrack(for track: MusicTrack, token: String) async throws -> SearchTrack? {
        let query = track.isrc.map { "isrc:\($0)" } ?? "track:\(track.title) artist:\(track.artist)"
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: "5")
        ]
        let response: TrackSearchResponse = try await get(url: components.url!, token: token)
        if let isrc = track.isrc?.lowercased(),
           let exact = response.tracks.items.first(where: { $0.externalIDs?.isrc?.lowercased() == isrc }) {
            return exact
        }
        return response.tracks.items.first
    }

    private func get<T: Decodable>(url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func sendJSON<T: Decodable>(path: String, method: String, token: String, body: [String: Any]) async throws -> T {
        let data = try await send(path: path, method: method, token: token, body: body)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func sendWithoutResponse(path: String, method: String, token: String, body: [String: Any]) async throws {
        _ = try await send(path: path, method: method, token: token, body: body)
    }

    private func send(path: String, method: String, token: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.spotify.com\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)
        return data
    }

    private func validAccessToken() async throws -> String {
        if let accessToken, expiresAt.timeIntervalSinceNow > 60 { return accessToken }
        if let refreshToken = keychain.refreshToken {
            do { return try await refresh(refreshToken) } catch { keychain.deleteRefreshToken() }
        }
        return try await authorize()
    }

    private func authorize() async throws -> String {
        let verifier = Self.randomURLSafeString(byteCount: 64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        let state = Self.randomURLSafeString(byteCount: 24)

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Configuration.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Configuration.redirectURI),
            URLQueryItem(name: "scope", value: Configuration.scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state)
        ]

        let callbackURL = try await startAuthenticationSession(url: components.url!)
        let callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let values = Dictionary(uniqueKeysWithValues: (callback?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        if let message = values["error"] { throw SpotifyError.authorization(message) }
        guard values["state"] == state, let code = values["code"], !code.isEmpty else {
            throw SpotifyError.invalidCallback
        }
        return try await exchangeCode(code, verifier: verifier)
    }

    private func startAuthenticationSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Configuration.callbackScheme) { [weak self] url, error in
                self?.authenticationSession = nil
                if let error { continuation.resume(throwing: error) }
                else if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: SpotifyError.invalidCallback) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authenticationSession = session
            guard session.start() else {
                authenticationSession = nil
                continuation.resume(throwing: SpotifyError.couldNotStartAuthentication)
                return
            }
        }
    }

    private func exchangeCode(_ code: String, verifier: String) async throws -> String {
        try await requestToken(parameters: [
            "client_id": Configuration.clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Configuration.redirectURI,
            "code_verifier": verifier
        ])
    }

    private func refresh(_ refreshToken: String) async throws -> String {
        try await requestToken(parameters: [
            "client_id": Configuration.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ])
    }

    private func requestToken(parameters: [String: String]) async throws -> String {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key.formURLEncoded)=\($0.value.formURLEncoded)" }
            .joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)
        let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = payload.accessToken
        expiresAt = Date().addingTimeInterval(TimeInterval(payload.expiresIn))
        if let refreshToken = payload.refreshToken { try keychain.save(refreshToken: refreshToken) }
        return payload.accessToken
    }

    private func fetchPages<Item: Decodable>(path: String, token: String, queryItems: [URLQueryItem] = []) async throws -> [Item] {
        var components = URLComponents(string: "https://api.spotify.com\(path)")!
        components.queryItems = [URLQueryItem(name: "limit", value: "50")] + queryItems
        var nextURL: URL? = components.url
        var items: [Item] = []

        while let url = nextURL {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.validate(response: response, data: data)
            let page = try JSONDecoder().decode(Page<Item>.self, from: data)
            items.append(contentsOf: page.items)
            nextURL = page.next.flatMap(URL.init(string:))
        }
        return items
    }

    private func map(_ playlist: PlaylistSummary, items: [PlaylistItem]) -> SharedPlaylist {
        let tracks = items.compactMap(\.item).enumerated().map { index, track in
            var artwork = AppDefaults.trackArtworks[index % AppDefaults.trackArtworks.count]
            artwork.imageURL = track.album.images?.first?.url
            return MusicTrack(
                id: track.id ?? "spotify-track-\(playlist.id)-\(index)",
                isrc: track.externalIDs?.isrc,
                title: track.name,
                artist: track.artists.map(\.name).joined(separator: ", "),
                album: track.album.name,
                duration: TimeInterval(track.durationMS) / 1_000,
                artwork: artwork
            )
        }
        var playlistArtwork = AppDefaults.spotifyArtwork
        playlistArtwork.imageURL = playlist.images?.first?.url
            ?? tracks.first(where: { $0.artwork.imageURL != nil })?.artwork.imageURL
        return SharedPlaylist(
            id: "spotify-\(playlist.id)", title: playlist.name,
            creator: AppDefaults.currentUser, message: nil, tracks: tracks,
            artwork: playlistArtwork, createdAt: .now,
            sourceURL: playlist.externalURLs.spotify.flatMap(URL.init(string:)), sourcePlatform: .spotify
        )
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error.message)
                ?? String(data: data, encoding: .utf8) ?? "알 수 없는 오류"
            if (response as? HTTPURLResponse)?.statusCode == 403 {
                throw SpotifyError.developmentModeAccess(message)
            }
            throw SpotifyError.api(statusCode: (response as? HTTPURLResponse)?.statusCode, message: message)
        }
    }
}

extension SpotifyLibraryService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

private struct SpotifyTokenStore {
    private let service = "sun.Munecting.spotify"
    private let account = "refresh-token-v2"

    var refreshToken: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(refreshToken: String) throws {
        deleteRefreshToken()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(refreshToken.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SpotifyError.keychain(status) }
    }

    func deleteRefreshToken() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", expiresIn = "expires_in", refreshToken = "refresh_token"
    }
}

private struct Page<Item: Decodable>: Decodable { let items: [Item]; let next: String? }
private struct PlaylistSummary: Decodable {
    let id: String; let name: String; let externalURLs: ExternalURLs; let images: [SpotifyImage]?
    enum CodingKeys: String, CodingKey { case id, name, images; case externalURLs = "external_urls" }
}
private struct PlaylistItem: Decodable { let item: SpotifyTrack? }
private struct SpotifyTrack: Decodable {
    let id: String?; let name: String; let durationMS: Int; let artists: [Artist]; let album: Album; let externalIDs: ExternalIDs?
    enum CodingKeys: String, CodingKey {
        case id, name, artists, album; case durationMS = "duration_ms"; case externalIDs = "external_ids"
    }
}
private struct Artist: Decodable { let name: String }
private struct Album: Decodable { let name: String; let images: [SpotifyImage]? }
private struct SpotifyImage: Decodable { let url: URL }
private struct ExternalIDs: Decodable { let isrc: String? }
private struct ExternalURLs: Decodable { let spotify: String? }
private struct CreatedPlaylist: Decodable {
    let id: String; let externalURLs: RequiredExternalURLs
    enum CodingKeys: String, CodingKey { case id; case externalURLs = "external_urls" }
}
private struct RequiredExternalURLs: Decodable { let spotify: String }
private struct TrackSearchResponse: Decodable { let tracks: TrackSearchPage }
private struct TrackSearchPage: Decodable { let items: [SearchTrack] }
private struct SearchTrack: Decodable {
    let uri: String; let externalIDs: ExternalIDs?; let album: Album?
    enum CodingKeys: String, CodingKey { case uri, album; case externalIDs = "external_ids" }
}
private struct APIErrorEnvelope: Decodable { let error: APIError }
private struct APIError: Decodable { let message: String }

private enum SpotifyError: LocalizedError {
    case authorization(String), invalidCallback, couldNotStartAuthentication
    case api(statusCode: Int?, message: String)
    case developmentModeAccess(String)
    case keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .authorization(let message): "Spotify 로그인이 취소되었거나 거부되었습니다: \(message)"
        case .invalidCallback: "Spotify 로그인 응답을 확인할 수 없습니다."
        case .couldNotStartAuthentication: "Spotify 로그인 화면을 열 수 없습니다."
        case .api(let statusCode, let message):
            "Spotify 요청에 실패했습니다\(statusCode.map { " (HTTP \($0))" } ?? ""): \(message)"
        case .developmentModeAccess(let message):
            "Spotify 개발 모드 접근이 거부됐습니다. 앱 소유자의 Premium 구독과 Dashboard의 허용 사용자를 확인해주세요.\n\nSpotify 응답: \(message)"
        case .keychain(let status): "Spotify 로그인 정보를 안전하게 저장하지 못했습니다. (\(status))"
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var formURLEncoded: String {
        addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? self
    }
}
