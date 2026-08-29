import Foundation
import Combine

@MainActor
final class PlaylistDetailViewModel: ObservableObject {
    enum ImportState: Equatable {
        case idle
        case importing
        case authenticationRequired(MusicPlatform)
        case completed(matchedCount: Int)
        case failed(message: String)
    }

    let playlist: SharedPlaylist
    @Published var selectedPlatform: MusicPlatform = .appleMusic
    @Published private(set) var importState: ImportState = .idle

    private let importUseCase: ImportPlaylistUseCase

    init(playlist: SharedPlaylist, importUseCase: ImportPlaylistUseCase) {
        self.playlist = playlist
        self.importUseCase = importUseCase
    }

    func importPlaylist() async {
        guard importState != .importing else { return }
        importState = .importing
        do {
            let receipt = try await importUseCase.execute(playlist: playlist, platform: selectedPlatform)
            importState = .completed(matchedCount: receipt.matchedTrackCount)
        } catch PlaylistImportError.authenticationRequired(let platform) {
            importState = .authenticationRequired(platform)
        } catch {
            importState = .failed(message: error.localizedDescription)
        }
    }

    func resetImport() { importState = .idle }
}
