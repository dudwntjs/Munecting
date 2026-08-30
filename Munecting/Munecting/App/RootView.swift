import SwiftUI

struct RootView: View {
    let container: AppContainer
    @State private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init(container: AppContainer) {
        self.container = container
    }

    var body: some View {
        @Bindable var state = state

        TabView(selection: $state.selectedTab) {
            Tab("홈", systemImage: "house.fill", value: AppState.Tab.home) {
                HomeView(
                    viewModel: HomeViewModel(playlists: container.playlists),
                    refreshID: state.inboxRevision,
                    onOpenPlaylist: {
                        state.presentedPlaylistIsReceived = true
                        state.presentedPlaylist = $0
                    }
                )
            }

            Tab("내 믹스", systemImage: "square.stack.fill", value: AppState.Tab.myMixes) {
                LibraryView(
                    viewModel: LibraryViewModel(playlists: container.playlists),
                    refreshID: state.libraryRevision,
                    onImport: { state.isImportingPlaylist = true },
                    onOpenPlaylist: {
                        state.presentedPlaylistIsReceived = false
                        state.presentedPlaylist = $0
                    }
                )
            }
        }
        .tint(AppTheme.accent)
        .sheet(item: $state.presentedPlaylist, onDismiss: {
            state.inboxRevision += 1
            state.libraryRevision += 1
        }) { playlist in
            PlaylistDetailView(
                playlist: playlist,
                repository: container.playlists,
                isReceived: state.presentedPlaylistIsReceived
            )
        }
        .sheet(isPresented: $state.isImportingPlaylist) {
            PlatformPlaylistImportView(repository: container.playlists) {
                state.libraryRevision += 1
                state.selectedTab = .myMixes
            }
        }
        .overlay(alignment: .top) {
            if let message = state.notificationMessage {
                Label(message, systemImage: "paperplane.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            await importSharedLinks()
        }
        .task(id: state.notificationMessage) {
            guard let displayedMessage = state.notificationMessage else { return }
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard state.notificationMessage == displayedMessage else { return }
            state.notificationMessage = nil
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await importSharedLinks() }
        }
        .onOpenURL { url in
            if SpotifyRemotePlayer.shared.handleCallback(url) { return }
            if url.scheme == "munecting", url.host == "receive" {
                Task { await importReceivedMix(from: url) }
                return
            }
            let supportedExtensions = ["munecting", "json"]
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else { return }
            Task { await importReceivedMix(from: url) }
        }
        .animation(.snappy, value: state.notificationMessage)
        .dynamicTypeSize(.large)
    }

    private func importSharedLinks() async {
        let links = ExternalShareInbox.drain()
        guard !links.isEmpty else { return }

        for link in links {
            try? await container.playlists.save(link.unresolvedPlaylist())
        }
        state.libraryRevision += 1
        state.selectedTab = .myMixes
        state.notificationMessage = "공유한 믹스 폴더를 내 믹스에 추가했어요"
    }

    private func importReceivedMix(from url: URL) async {
        do {
            let playlist = if url.scheme == "munecting" {
                try MixTransferLink.decode(from: url)
            } else {
                try MixTransferImporter.decode(from: url)
            }
            try await container.playlists.receive(playlist)
            state.inboxRevision += 1
            state.selectedTab = .home
            state.notificationMessage = "‘\(playlist.title)’ 믹스를 받았어요"
        } catch {
            state.notificationMessage = "받은 믹스를 열 수 없어요"
        }
    }
}
