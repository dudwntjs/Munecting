import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    enum ViewState { case loading, loaded, failed(String) }

    private(set) var state: ViewState = .loading
    private(set) var receivedPlaylists: [SharedPlaylist] = []
    private let playlists: any PlaylistRepository

    init(playlists: any PlaylistRepository) {
        self.playlists = playlists
    }

    func load() async {
        state = .loading
        do {
            receivedPlaylists = try await playlists.receivedPlaylists()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func delete(_ playlist: SharedPlaylist) async {
        do {
            try await playlists.deleteReceived(id: playlist.id)
            await load()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
