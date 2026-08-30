import Foundation
import MusicKit

struct AppleMusicPlaylistExporter {
    func create(from playlist: SharedPlaylist) async throws -> PlaylistExportResult {
        let status = await MusicAuthorization.request()
        guard status == .authorized else { throw PlaylistExportError.authorizationRequired(.appleMusic) }
        guard !playlist.tracks.isEmpty else { throw PlaylistExportError.emptyPlaylist }

        var songs: [Song] = []
        var unmatched: [MusicTrack] = []
        for track in playlist.tracks {
            if let song = try await match(track) { songs.append(song) }
            else { unmatched.append(track) }
        }
        guard !songs.isEmpty else { throw PlaylistExportError.noTracksMatched }

        let created = try await MusicLibrary.shared.createPlaylist(
            name: playlist.title,
            description: playlist.message,
            authorDisplayName: "Munecting",
            items: songs
        )
        let url = created.url ?? URL(string: "music://")!
        return PlaylistExportResult(url: url, matchedCount: songs.count, unmatchedTracks: unmatched)
    }

    private func match(_ track: MusicTrack) async throws -> Song? {
        var request = MusicCatalogSearchRequest(term: "\(track.title) \(track.artist)", types: [Song.self])
        request.limit = 10
        let songs = try await request.response().songs

        if let isrc = track.isrc?.lowercased(),
           let exact = songs.first(where: { $0.isrc?.lowercased() == isrc }) {
            return exact
        }
        let expectedTitle = normalized(track.title)
        let expectedArtist = normalized(track.artist)
        return songs.first {
            normalized($0.title) == expectedTitle &&
            (normalized($0.artistName).contains(expectedArtist) || expectedArtist.contains(normalized($0.artistName)))
        } ?? songs.first
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }
}

struct PlaylistExportResult {
    let url: URL
    let matchedCount: Int
    let unmatchedTracks: [MusicTrack]
}

enum PlaylistExportError: LocalizedError {
    case authorizationRequired(MusicPlatform)
    case emptyPlaylist
    case noTracksMatched

    var errorDescription: String? {
        switch self {
        case .authorizationRequired(let platform): "\(platform.displayName) 접근 권한이 필요합니다."
        case .emptyPlaylist: "이 믹스에는 생성할 곡 정보가 없습니다."
        case .noTracksMatched: "대상 음악 플랫폼에서 일치하는 곡을 찾지 못했습니다."
        }
    }
}
