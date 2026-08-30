import SwiftUI

struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @State private var isShowingNotifications = false
    @State private var notificationSelection: SharedPlaylist?
    @AppStorage("home.seenNotificationIDs") private var seenNotificationIDsData = "[]"
    let refreshID: Int
    let onOpenPlaylist: (SharedPlaylist) -> Void

    init(viewModel: HomeViewModel, refreshID: Int, onOpenPlaylist: @escaping (SharedPlaylist) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.refreshID = refreshID
        self.onOpenPlaylist = onOpenPlaylist
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.receivedPlaylists.isEmpty {
                    EmptyStateView(symbol: "tray", title: "아직 받은 뮤직 폴더가 없어요", message: "친구가 AirDrop으로 믹스를 보내면\nMunecting으로 열어 받을 수 있어요.")
                } else {
                    List(viewModel.receivedPlaylists) { playlist in
                        Button { onOpenPlaylist(playlist) } label: {
                            ReceivedPlaylistRow(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(AppTheme.surface)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await viewModel.delete(playlist) }
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AppTheme.background)
            .navigationTitle("친구가 보내온 음악")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        markAllNotificationsAsSeen()
                        isShowingNotifications = true
                    } label: {
                        Image(systemName: unreadNotificationCount > 0 ? "bell.badge.fill" : "bell")
                            .foregroundStyle(AppTheme.accent)
                    }
                    .accessibilityLabel("알림")
                    .accessibilityValue(unreadNotificationCount > 0 ? "새 알림 (unreadNotificationCount)개" : "새 알림 없음")
                }
            }
        }
        .task(id: refreshID) { await viewModel.load() }
        .sheet(isPresented: $isShowingNotifications, onDismiss: openSelectedNotification) {
            MixNotificationView(
                playlists: viewModel.receivedPlaylists,
                onSelect: { playlist in
                    notificationSelection = playlist
                    isShowingNotifications = false
                }
            )
        }
    }

    private var seenNotificationIDs: Set<String> {
        guard let data = seenNotificationIDsData.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(ids)
    }

    private var unreadNotificationCount: Int {
        viewModel.receivedPlaylists.reduce(into: 0) { count, playlist in
            if !seenNotificationIDs.contains(playlist.id) { count += 1 }
        }
    }

    private func markAllNotificationsAsSeen() {
        let updatedIDs = seenNotificationIDs.union(viewModel.receivedPlaylists.map(\.id))
        guard let data = try? JSONEncoder().encode(Array(updatedIDs).sorted()),
              let value = String(data: data, encoding: .utf8)
        else { return }
        seenNotificationIDsData = value
    }

    private func openSelectedNotification() {
        guard let playlist = notificationSelection else { return }
        notificationSelection = nil
        onOpenPlaylist(playlist)
    }
}

private struct MixNotificationView: View {
    let playlists: [SharedPlaylist]
    let onSelect: (SharedPlaylist) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if playlists.isEmpty {
                    EmptyStateView(
                        symbol: "bell.slash",
                        title: "아직 알림이 없어요",
                        message: "친구에게 받은 믹스가 여기에 표시돼요."
                    )
                } else {
                    List(playlists) { playlist in
                        Button { onSelect(playlist) } label: {
                            HStack(spacing: 12) {
                                ArtworkView(artwork: playlist.displayArtwork, cornerRadius: 10)
                                    .frame(width: 48, height: 48)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(playlist.creator.displayName)님이 믹스를 보냈어요")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(playlist.title)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text(playlist.createdAt, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(AppTheme.surface)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AppTheme.background)
            .navigationTitle("알림")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }
}

private struct ReceivedPlaylistRow: View {
    let playlist: SharedPlaylist

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(artwork: playlist.displayArtwork, cornerRadius: 12)
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 5) {
                Text(playlist.title)
                    .font(AppTheme.Typography.rowTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.tail)
                Text("\(playlist.creator.displayName)님이 보냄 · \(playlist.tracks.count)곡")
                    .font(AppTheme.Typography.metadata).foregroundStyle(.secondary)
                if let message = playlist.message, !message.isEmpty {
                    Label(message, systemImage: "quote.opening")
                        .font(AppTheme.Typography.message)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}
