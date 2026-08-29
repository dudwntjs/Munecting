import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

@MainActor
final class YouTubeMusicService: NSObject {
    private enum Configuration {
        static let clientID = "196241836357-0musoe1s12c9o5st6hf5ninu39uemk8u.apps.googleusercontent.com"
        static let callbackScheme = "com.googleusercontent.apps.196241836357-0musoe1s12c9o5st6hf5ninu39uemk8u"
        static let redirectURI = "\(callbackScheme):/oauthredirect"
        static let scope = "https://www.googleapis.com/auth/youtube.force-ssl"
    }

    private var authenticationSession: ASWebAuthenticationSession?
    private var accessToken: String?
    private var expiresAt: Date = .distantPast
    private let tokenStore = YouTubeTokenStore()

    func playlists() async throws -> [SharedPlaylist] {
        let token = try await validAccessToken()
        let summaries: [YouTubePlaylist] = try await fetchPages(
            path: "/playlists",
            token: token,
            queryItems: [
                URLQueryItem(name: "part", value: "snippet,contentDetails"),
                URLQueryItem(name: "mine", value: "true")
            ]
        )

        var result: [SharedPlaylist] = []
        for summary in summaries {
            let items: [YouTubePlaylistItem] = try await fetchPages(
                path: "/playlistItems",
                token: token,
                queryItems: [
                    URLQueryItem(name: "part", value: "snippet,contentDetails"),
                    URLQueryItem(name: "playlistId", value: summary.id)
                ]
            )
            result.append(map(summary, items: items))
        }
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func createPlaylist(from playlist: SharedPlaylist) async throws -> PlaylistExportResult {
        guard !playlist.tracks.isEmpty else { throw PlaylistExportError.emptyPlaylist }
        let token = try await validAccessToken()
        let created: YouTubePlaylist = try await sendJSON(
            path: "/playlists?part=snippet,status",
            token: token,
            body: [
                "snippet": ["title": playlist.title, "description": playlist.message ?? "Munecting에서 받은 믹스"],
                "status": ["privacyStatus": "private"]
            ]
        )

        var unmatched: [MusicTrack] = []
        var matchedCount = 0
        for track in playlist.tracks {
            guard let video = try await search(track, token: token) else {
                unmatched.append(track)
                continue
            }
            try await sendWithoutResponse(
                path: "/playlistItems?part=snippet",
                token: token,
                body: [
                    "snippet": [
                        "playlistId": created.id,
                        "resourceId": ["kind": "youtube#video", "videoId": video.id.videoId]
                    ]
                ]
            )
            matchedCount += 1
        }
        guard matchedCount > 0 else { throw PlaylistExportError.noTracksMatched }
        return PlaylistExportResult(
            url: URL(string: "https://music.youtube.com/playlist?list=\(created.id)")!,
            matchedCount: matchedCount,
            unmatchedTracks: unmatched
        )
    }

    func musicURL(for track: MusicTrack) async throws -> URL? {
        let token = try await validAccessToken()
        guard let videoID = try await search(track, token: token)?.id.videoId else { return nil }
        return URL(string: "https://music.youtube.com/watch?v=\(videoID)")
    }

    func artworkURL(for track: MusicTrack) async throws -> URL? {
        let token = try await validAccessToken()
        return try await search(track, token: token)?.snippet.thumbnails.best
    }

    private func search(_ track: MusicTrack, token: String) async throws -> YouTubeSearchItem? {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "videoCategoryId", value: "10"),
            URLQueryItem(name: "maxResults", value: "5"),
            URLQueryItem(name: "q", value: "\(track.title) \(track.artist)")
        ]
        let response: YouTubeSearchResponse = try await get(url: components.url!, token: token)
        return response.items.first
    }

    private func fetchPages<Item: Decodable>(path: String, token: String, queryItems: [URLQueryItem]) async throws -> [Item] {
        var pageToken: String?
        var result: [Item] = []
        repeat {
            var components = URLComponents(string: "https://www.googleapis.com/youtube/v3\(path)")!
            components.queryItems = queryItems + [URLQueryItem(name: "maxResults", value: "50")]
            if let pageToken { components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: YouTubePage<Item> = try await get(url: components.url!, token: token)
            result.append(contentsOf: page.items)
            pageToken = page.nextPageToken
        } while pageToken != nil
        return result
    }

    private func get<T: Decodable>(url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func sendJSON<T: Decodable>(path: String, token: String, body: [String: Any]) async throws -> T {
        let data = try await send(path: path, token: token, body: body)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func sendWithoutResponse(path: String, token: String, body: [String: Any]) async throws {
        _ = try await send(path: path, token: token, body: body)
    }

    private func send(path: String, token: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/youtube/v3\(path)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        return data
    }

    private func validAccessToken() async throws -> String {
        if let accessToken, expiresAt.timeIntervalSinceNow > 60 { return accessToken }
        if let refreshToken = tokenStore.refreshToken,
           let refreshed = try? await refresh(refreshToken) { return refreshed }
        return try await authorize()
    }

    private func authorize() async throws -> String {
        let verifier = Self.randomURLSafeString(byteCount: 64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        let state = Self.randomURLSafeString(byteCount: 24)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: Configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Configuration.scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: Configuration.callbackScheme) { url, error in
                if let error { continuation.resume(throwing: error) }
                else if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: YouTubeError.invalidCallback) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authenticationSession = session
            guard session.start() else {
                continuation.resume(throwing: YouTubeError.couldNotStartAuthentication)
                return
            }
        }
        guard let values = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
              values.first(where: { $0.name == "state" })?.value == state,
              let code = values.first(where: { $0.name == "code" })?.value
        else { throw YouTubeError.invalidCallback }

        let token = try await exchange(code: code, verifier: verifier)
        return apply(token)
    }

    private func exchange(code: String, verifier: String) async throws -> GoogleTokenResponse {
        try await tokenRequest([
            "client_id": Configuration.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": Configuration.redirectURI
        ])
    }

    private func refresh(_ refreshToken: String) async throws -> String {
        let token: GoogleTokenResponse = try await tokenRequest([
            "client_id": Configuration.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])
        return apply(token)
    }

    private func tokenRequest(_ parameters: [String: String]) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters.map { "\($0.key.urlEncoded)=\($0.value.urlEncoded)" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        return try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
    }

    private func apply(_ token: GoogleTokenResponse) -> String {
        accessToken = token.accessToken
        expiresAt = .now.addingTimeInterval(TimeInterval(token.expiresIn))
        if let refreshToken = token.refreshToken { try? tokenStore.save(refreshToken) }
        return token.accessToken
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(GoogleAPIError.self, from: data).error.message)
                ?? String(data: data, encoding: .utf8) ?? "YouTube 요청에 실패했습니다."
            throw YouTubeError.api(message)
        }
    }

    private func map(_ playlist: YouTubePlaylist, items: [YouTubePlaylistItem]) -> SharedPlaylist {
        let tracks = items.enumerated().compactMap { index, item -> MusicTrack? in
            guard let videoID = item.contentDetails?.videoId ?? item.snippet.resourceId?.videoId else { return nil }
            var artwork = AppDefaults.trackArtworks[index % AppDefaults.trackArtworks.count]
            artwork.imageURL = item.snippet.thumbnails.best
            return MusicTrack(
                id: "youtube-\(videoID)", isrc: nil,
                title: item.snippet.title,
                artist: item.snippet.videoOwnerChannelTitle ?? "YouTube Music",
                album: "", duration: 0, artwork: artwork
            )
        }
        var artwork = AppDefaults.youtubeMusicArtwork
        artwork.imageURL = playlist.snippet.thumbnails.best ?? tracks.first?.artwork.imageURL
        return SharedPlaylist(
            id: "youtube-\(playlist.id)", title: playlist.snippet.title,
            creator: AppDefaults.currentUser, message: playlist.snippet.description,
            tracks: tracks, artwork: artwork, createdAt: .now,
            sourceURL: URL(string: "https://music.youtube.com/playlist?list=\(playlist.id)"),
            sourcePlatform: .youtubeMusic
        )
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

extension YouTubeMusicService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

private struct YouTubePage<Item: Decodable>: Decodable { let items: [Item]; let nextPageToken: String? }
private struct YouTubePlaylist: Decodable { let id: String; let snippet: YouTubeSnippet }
private struct YouTubePlaylistItem: Decodable { let snippet: YouTubeSnippet; let contentDetails: YouTubeContentDetails? }
private struct YouTubeContentDetails: Decodable { let videoId: String? }
private struct YouTubeSnippet: Decodable {
    let title: String
    let description: String?
    let thumbnails: YouTubeThumbnails
    let videoOwnerChannelTitle: String?
    let resourceId: YouTubeResourceID?
}
private struct YouTubeResourceID: Decodable { let videoId: String? }
private struct YouTubeSearchResponse: Decodable { let items: [YouTubeSearchItem] }
private struct YouTubeSearchItem: Decodable { let id: YouTubeSearchID; let snippet: YouTubeSnippet }
private struct YouTubeSearchID: Decodable { let videoId: String }
private struct YouTubeThumbnails: Decodable {
    let maxres: YouTubeThumbnail?; let standard: YouTubeThumbnail?; let high: YouTubeThumbnail?
    let medium: YouTubeThumbnail?; let `default`: YouTubeThumbnail?
    var best: URL? { maxres?.url ?? standard?.url ?? high?.url ?? medium?.url ?? `default`?.url }
}
private struct YouTubeThumbnail: Decodable { let url: URL }
private struct GoogleTokenResponse: Decodable {
    let accessToken: String; let expiresIn: Int; let refreshToken: String?
    enum CodingKeys: String, CodingKey { case accessToken = "access_token", expiresIn = "expires_in", refreshToken = "refresh_token" }
}
private struct GoogleAPIError: Decodable { let error: GoogleAPIErrorDetail }
private struct GoogleAPIErrorDetail: Decodable { let message: String }

private enum YouTubeError: LocalizedError {
    case invalidCallback, couldNotStartAuthentication, api(String), keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .invalidCallback: "Google 로그인 응답이 올바르지 않습니다."
        case .couldNotStartAuthentication: "Google 로그인을 시작할 수 없습니다."
        case .api(let message): message
        case .keychain(let status): "Google 로그인 정보를 저장하지 못했습니다. (\(status))"
        }
    }
}

private struct YouTubeTokenStore {
    private let service = "sun.Munecting.youtube"
    private let account = "refresh-token"
    var refreshToken: String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func save(_ value: String) throws {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw YouTubeError.keychain(status) }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var urlEncoded: String { addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))) ?? self }
}
