import Foundation
import MusicKit
import SpotifyiOS
import UIKit

@MainActor
struct TrackPlaybackService {
    private let spotify = SpotifyLibraryService()
    private let youtubeMusic = YouTubeMusicService()

    func play(_ track: MusicTrack, on platform: MusicPlatform) async throws {
        switch platform {
        case .appleMusic:
            let status = await MusicAuthorization.request()
            guard status == .authorized else { throw TrackPlaybackError.authorizationRequired(.appleMusic) }
            guard let song = try await appleMusicSong(for: track) else { throw TrackPlaybackError.trackNotFound }
            let player = SystemMusicPlayer.shared
            player.queue = MusicPlayer.Queue(for: [song])
            try await player.play()
        case .spotify:
            guard let uri = try await spotify.spotifyURI(for: track) else { throw TrackPlaybackError.trackNotFound }
            SpotifyRemotePlayer.shared.play(uri: uri)
        case .youtubeMusic:
            guard let url = try await youtubeMusic.musicURL(for: track) else { throw TrackPlaybackError.trackNotFound }
            await UIApplication.shared.open(url)
        }
    }

    private func appleMusicSong(for track: MusicTrack) async throws -> Song? {
        var request = MusicCatalogSearchRequest(term: "\(track.title) \(track.artist)", types: [Song.self])
        request.limit = 10
        let songs = try await request.response().songs
        if let isrc = track.isrc?.lowercased(),
           let exact = songs.first(where: { $0.isrc?.lowercased() == isrc }) {
            return exact
        }
        return songs.first
    }
}

@MainActor
final class SpotifyRemotePlayer: NSObject, SPTAppRemoteDelegate {
    static let shared = SpotifyRemotePlayer()

    private let configuration = SPTConfiguration(
        clientID: "c7a8e00cc75c4ccaafabc735603a1ab6",
        redirectURL: URL(string: "munecting-spotify-login://callback")!
    )
    private lazy var appRemote: SPTAppRemote = {
        let remote = SPTAppRemote(configuration: configuration, logLevel: .none)
        remote.delegate = self
        return remote
    }()
    private var pendingURI: String?
    private(set) var lastError: Error?

    func play(uri: String) {
        pendingURI = uri
        lastError = nil
        if appRemote.isConnected {
            appRemote.playerAPI?.play(uri, callback: playbackCallback)
        } else {
            appRemote.authorizeAndPlayURI(uri)
        }
    }

    func handleCallback(_ url: URL) -> Bool {
        guard url.scheme == "munecting-spotify-login" else { return false }
        let parameters = appRemote.authorizationParameters(from: url)
        if let accessToken = parameters?[SPTAppRemoteAccessTokenKey] {
            appRemote.connectionParameters.accessToken = accessToken
            appRemote.connect()
        }
        return true
    }

    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        guard let pendingURI else { return }
        appRemote.playerAPI?.play(pendingURI, callback: playbackCallback)
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        lastError = error
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        lastError = error
    }

    private var playbackCallback: SPTAppRemoteCallback {
        { [weak self] _, error in self?.lastError = error }
    }
}

enum TrackPlaybackError: LocalizedError {
    case authorizationRequired(MusicPlatform)
    case trackNotFound

    var errorDescription: String? {
        switch self {
        case .authorizationRequired(let platform): "\(platform.displayName) 접근 권한이 필요합니다."
        case .trackNotFound: "선택한 음악 플랫폼에서 이 곡을 찾지 못했습니다."
        }
    }
}
