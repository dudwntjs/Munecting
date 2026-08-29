import Foundation

enum AppDefaults {
    static let currentUser = UserSummary(id: "local-user", displayName: "나", avatarInitial: "나")
    static let defaultArtwork = ArtworkStyle(
        primary: .init(red: 0.28, green: 0.18, blue: 0.75),
        secondary: .init(red: 0.94, green: 0.34, blue: 0.48),
        symbol: "music.note.list"
    )
    static let appleMusicArtwork = ArtworkStyle(
        primary: .init(red: 0.98, green: 0.20, blue: 0.36),
        secondary: .init(red: 0.62, green: 0.18, blue: 0.74),
        symbol: "music.note"
    )
    static let spotifyArtwork = ArtworkStyle(
        primary: .init(red: 0.12, green: 0.84, blue: 0.38),
        secondary: .init(red: 0.03, green: 0.32, blue: 0.16),
        symbol: "waveform"
    )
    static let youtubeMusicArtwork = ArtworkStyle(
        primary: .init(red: 0.95, green: 0.05, blue: 0.08),
        secondary: .init(red: 0.45, green: 0.01, blue: 0.03),
        symbol: "play.circle.fill"
    )
    static let trackArtworks: [ArtworkStyle] = [
        appleMusicArtwork,
        .init(primary: .init(red: 0.16, green: 0.32, blue: 0.72), secondary: .init(red: 0.34, green: 0.18, blue: 0.58), symbol: "waveform"),
        .init(primary: .init(red: 0.08, green: 0.58, blue: 0.66), secondary: .init(red: 0.42, green: 0.20, blue: 0.68), symbol: "music.quarternote.3")
    ]
}

struct EmptyMusicCatalogRepository: MusicCatalogRepository {
    func trendingTracks() async throws -> [MusicTrack] { [] }
    func search(query: String) async throws -> [MusicTrack] { [] }
}

struct UnavailableMusicPlatformGateway: MusicPlatformGateway {
    let platform: MusicPlatform

    func connectionState() async -> PlatformConnectionState { .disconnected }
    func connect() async throws { throw PlaylistImportError.serviceUnavailable }
    func importPlaylist(_ playlist: SharedPlaylist) async throws -> PlaylistImportReceipt {
        throw PlaylistImportError.serviceUnavailable
    }
}

struct UnavailableMusicPlatformGatewayFactory: MusicPlatformGatewayFactory {
    func gateway(for platform: MusicPlatform) -> any MusicPlatformGateway {
        UnavailableMusicPlatformGateway(platform: platform)
    }
}
