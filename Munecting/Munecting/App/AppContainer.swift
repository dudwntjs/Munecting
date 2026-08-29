import Foundation
import SwiftData

struct AppContainer {
    let playlists: any PlaylistRepository
    let catalog: any MusicCatalogRepository
    let platforms: any MusicPlatformGatewayFactory
    let modelContainer: ModelContainer

    static func live() -> AppContainer {
        do {
            let schema = Schema([PlaylistRecord.self, TrackRecord.self])
            let configuration = ModelConfiguration("Munecting", schema: schema)
            let modelContainer = try ModelContainer(for: schema, configurations: configuration)
            return AppContainer(
                playlists: SwiftDataPlaylistRepository(modelContainer: modelContainer),
                catalog: EmptyMusicCatalogRepository(),
                platforms: UnavailableMusicPlatformGatewayFactory(),
                modelContainer: modelContainer
            )
        } catch {
            fatalError("SwiftData 저장소를 만들 수 없습니다: \(error)")
        }
    }
}
