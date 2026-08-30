import Foundation

protocol PlaylistRepository: Sendable {
    func receivedPlaylists() async throws -> [SharedPlaylist]
    func savedPlaylists() async throws -> [SharedPlaylist]
    func save(_ playlist: SharedPlaylist) async throws
    func receive(_ playlist: SharedPlaylist) async throws
    func delete(id: SharedPlaylist.ID) async throws
    func deleteReceived(id: SharedPlaylist.ID) async throws
}

protocol MusicCatalogRepository: Sendable {
    func trendingTracks() async throws -> [MusicTrack]
    func search(query: String) async throws -> [MusicTrack]
}

protocol MusicPlatformGateway: Sendable {
    var platform: MusicPlatform { get }
    func connectionState() async -> PlatformConnectionState
    func connect() async throws
    func importPlaylist(_ playlist: SharedPlaylist) async throws -> PlaylistImportReceipt
}

enum PlatformConnectionState: Sendable {
    case connected(accountName: String)
    case disconnected
}

protocol MusicPlatformGatewayFactory: Sendable {
    func gateway(for platform: MusicPlatform) -> any MusicPlatformGateway
}

struct ImportPlaylistUseCase: Sendable {
    private let gateways: any MusicPlatformGatewayFactory

    init(gateways: any MusicPlatformGatewayFactory) {
        self.gateways = gateways
    }

    func execute(playlist: SharedPlaylist, platform: MusicPlatform) async throws -> PlaylistImportReceipt {
        let gateway = gateways.gateway(for: platform)
        guard case .connected = await gateway.connectionState() else {
            throw PlaylistImportError.authenticationRequired(platform)
        }
        return try await gateway.importPlaylist(playlist)
    }
}
