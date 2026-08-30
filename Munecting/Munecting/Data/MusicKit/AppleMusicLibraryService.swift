import Foundation
import MusicKit

struct AppleMusicLibraryService {
    func requestAuthorization() async -> MusicAuthorization.Status {
        await MusicAuthorization.request()
    }

    func playlists() async throws -> [SharedPlaylist] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw AppleMusicLibraryError.authorizationRequired
        }

        var request = MusicLibraryRequest<MusicKit.Playlist>()
        request.limit = 100
        let response = try await request.response()

        var results: [SharedPlaylist] = []
        for playlist in response.items {
            results.append(await map(playlist))
        }
        return results.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func artworkURL(for track: MusicTrack) async -> URL? {
        await catalogArtworkURL(title: track.title, artist: track.artist, isrc: track.isrc)
    }

    private func map(_ playlist: MusicKit.Playlist) async -> SharedPlaylist {
        let detailed = try? await playlist.with([.entries])
        var tracks: [MusicTrack] = []
        for entry in detailed?.entries ?? [] {
            let imageURL: URL?
            if let libraryArtworkURL = entry.artwork?.url(width: 300, height: 300) {
                imageURL = libraryArtworkURL
            } else {
                imageURL = await catalogArtworkURL(
                    title: entry.title,
                    artist: entry.artistName,
                    isrc: entry.isrc
                )
            }
            tracks.append(MusicTrack(
                id: entry.id.rawValue,
                isrc: entry.isrc,
                title: entry.title,
                artist: entry.artistName,
                album: entry.albumTitle ?? "",
                duration: entry.duration ?? 0,
                artwork: artwork(for: entry.position, imageURL: imageURL)
            ))
        }

        var playlistArtwork = artwork(for: playlist)
        if playlistArtwork.imageURL == nil,
           let firstTrackArtwork = tracks.first(where: { $0.artwork.imageURL != nil })?.artwork {
            playlistArtwork = firstTrackArtwork
        }

        return SharedPlaylist(
            id: "appleMusic-\(playlist.id.rawValue)", title: playlist.name,
            creator: AppDefaults.currentUser, message: nil, tracks: tracks,
            artwork: playlistArtwork,
            createdAt: playlist.libraryAddedDate ?? .now,
            sourceURL: playlist.url, sourcePlatform: .appleMusic
        )
    }

    private func artwork(for position: Int, imageURL: URL?) -> ArtworkStyle {
        let variants = AppDefaults.trackArtworks
        var style = variants[position % variants.count]
        style.imageURL = imageURL
        return style
    }

    private func artwork(for playlist: MusicKit.Playlist) -> ArtworkStyle {
        var style = AppDefaults.appleMusicArtwork
        style.imageURL = playlist.artwork?.url(width: 600, height: 600)
        return style
    }

    private func catalogArtworkURL(title: String, artist: String, isrc: String?) async -> URL? {
        var request = MusicCatalogSearchRequest(term: "\(title) \(artist)", types: [Song.self])
        request.limit = 10
        guard let songs = try? await request.response().songs else { return nil }
        let song: Song?
        if let isrc = isrc?.lowercased() {
            song = songs.first(where: { $0.isrc?.lowercased() == isrc }) ?? songs.first
        } else {
            song = songs.first
        }
        return song?.artwork?.url(width: 300, height: 300)
    }
}

enum AppleMusicLibraryError: LocalizedError {
    case authorizationRequired

    var errorDescription: String? { "Apple Music 보관함 접근 권한이 필요합니다." }
}
