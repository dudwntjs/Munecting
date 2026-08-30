import Observation

@MainActor
@Observable
final class AppState {
    enum Tab: Hashable { case home, myMixes }

    var selectedTab: Tab = .home
    var presentedPlaylist: SharedPlaylist?
    var presentedPlaylistIsReceived = false
    var isImportingPlaylist = false
    var inboxRevision = 0
    var libraryRevision = 0
    var notificationMessage: String?
}
