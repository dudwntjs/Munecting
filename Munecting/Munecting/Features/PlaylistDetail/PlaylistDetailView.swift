import SwiftUI

struct PlaylistDetailView: View {
    @State private var playlist: SharedPlaylist
    @State private var exportingPlatform: MusicPlatform?
    @State private var errorMessage: String?
    @State private var isEditing = false
    @State private var spotify = SpotifyLibraryService()
    @State private var youtubeMusic = YouTubeMusicService()
    @State private var playingTrackID: MusicTrack.ID?
    @State private var isEnrichingArtwork = false
    let repository: any PlaylistRepository
    let isReceived: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("preferredMusicPlatform") private var preferredPlatform = MusicPlatform.appleMusic.rawValue

    private var platform: MusicPlatform {
        MusicPlatform(rawValue: preferredPlatform) ?? .appleMusic
    }

    init(playlist: SharedPlaylist, repository: any PlaylistRepository, isReceived: Bool) {
        _playlist = State(initialValue: playlist)
        self.repository = repository
        self.isReceived = isReceived
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        ArtworkView(artwork: playlist.displayArtwork, cornerRadius: 14)
                            .frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(playlist.title)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .truncationMode(.tail)
                            Text("\(playlist.creator.displayName) · \(playlist.tracks.count)곡")
                                .font(AppTheme.Typography.metadata)
                                .foregroundStyle(.secondary)
                            if let sourcePlatform = playlist.sourcePlatform {
                                Label(sourcePlatform.displayName, systemImage: sourcePlatform.symbol)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(sourcePlatform.tint)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let message = playlist.message, !message.isEmpty {
                    Section("보낸 메세지") {
                        Label {
                            Text(message)
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "quote.opening")
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                }
                Section {
                    ForEach(MusicPlatform.allCases) { musicPlatform in
                        Button {
                            Task { await createOrOpenPlaylist(on: musicPlatform) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: musicPlatform.symbol)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(musicPlatform.tint, in: RoundedRectangle(cornerRadius: 10))
                                Text(musicPlatform.displayName)
                                    .font(AppTheme.Typography.button)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if exportingPlatform == musicPlatform {
                                    ProgressView().tint(musicPlatform.tint)
                                } else if platformURL(for: musicPlatform) != nil {
                                    Text("열기")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 14)
                                        .frame(minHeight: 34)
                                        .background(musicPlatform.tint, in: Capsule())
                                } else {
                                    Image(systemName: "plus")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 34, height: 34)
                                        .background(musicPlatform.tint, in: Circle())
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(exportingPlatform != nil)
                    }
                } header: {
                    Text("음악 앱에서 열기")
                }

                Section {
                    HStack(spacing: 10) {
                        ForEach(MusicPlatform.allCases) { musicPlatform in
                            Button {
                                preferredPlatform = musicPlatform.rawValue
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: musicPlatform.symbol)
                                    Text(musicPlatform.displayName)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                    Spacer(minLength: 0)
                                    if platform == musicPlatform {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                    }
                                }
                                .font(.subheadline.weight(platform == musicPlatform ? .bold : .medium))
                                .foregroundStyle(platform == musicPlatform ? musicPlatform.tint : Color.secondary)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            platform == musicPlatform ? musicPlatform.tint : Color.secondary.opacity(0.28),
                                            lineWidth: platform == musicPlatform ? 1.5 : 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(playingTrackID != nil)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("곡 재생 플랫폼")
                } footer: {
                    Text("아래 곡을 누르면 선택한 음악 앱에서 재생됩니다.")
                }

                Section {
                    if playlist.tracks.isEmpty {
                        ContentUnavailableView {
                            Label("폴더 안의 노래 정보가 없어요", systemImage: "music.note.list")
                        } description: {
                            Text("외부 음악 앱에서 링크만 받은 믹스예요.\n곡 목록이 포함된 Munecting 파일로 공유하면 여기에 전체 곡이 표시됩니다.")
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(Array(playlist.tracks.enumerated()), id: \.element.id) { index, track in
                            Button { Task { await play(track) } } label: {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 20)
                                    ArtworkView(artwork: track.artwork, cornerRadius: 8).frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.title).font(AppTheme.Typography.rowTitle).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.85)
                                        Text(track.artist).font(AppTheme.Typography.metadata).foregroundStyle(.secondary).lineLimit(1)
                                        if !track.album.isEmpty {
                                            Text(track.album).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if playingTrackID == track.id {
                                        ProgressView().tint(platform.tint)
                                    } else {
                                        Image(systemName: "play.fill").foregroundStyle(platform.tint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(playingTrackID != nil)
                        }
                    }
                } header: {
                    Text(playlist.tracks.isEmpty ? "폴더 안의 노래" : "폴더 안의 노래 \(playlist.tracks.count)곡")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle(playlist.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("수정", systemImage: "pencil") { isEditing = true }
                }
            }
            .sheet(isPresented: $isEditing) {
                EditMixView(playlist: playlist) { title, message, artwork in
                    await updatePlaylist(title: title, message: message, artwork: artwork)
                }
            }
            .alert("작업을 완료하지 못했어요", isPresented: errorBinding) {
                Button("확인") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task(id: playlist.id) {
                await enrichMissingArtwork()
            }
        }
    }

    private func createOrOpenPlaylist(on musicPlatform: MusicPlatform) async {
        if let existingURL = platformURL(for: musicPlatform) {
            openURL(existingURL)
            return
        }
        exportingPlatform = musicPlatform
        defer { exportingPlatform = nil }
        do {
            let result = switch musicPlatform {
            case .appleMusic: try await AppleMusicPlaylistExporter().create(from: playlist)
            case .spotify: try await spotify.createPlaylist(from: playlist)
            case .youtubeMusic: try await youtubeMusic.createPlaylist(from: playlist)
            }
            playlist.platformCopies[musicPlatform] = result.url
            if isReceived { try await repository.receive(playlist) }
            else { try await repository.save(playlist) }
            openURL(result.url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func platformURL(for musicPlatform: MusicPlatform) -> URL? {
        if let copiedURL = playlist.platformCopies[musicPlatform] { return copiedURL }
        guard playlist.sourcePlatform == musicPlatform else { return nil }
        return playlist.sourceURL
    }

    private func updatePlaylist(title: String, message: String?, artwork: ArtworkStyle) async -> Bool {
        let updated = SharedPlaylist(
            id: playlist.id,
            title: title,
            creator: playlist.creator,
            message: message,
            tracks: playlist.tracks,
            artwork: artwork,
            createdAt: playlist.createdAt,
            sourceURL: playlist.sourceURL,
            sourcePlatform: playlist.sourcePlatform,
            platformCopies: playlist.platformCopies
        )
        do {
            if isReceived { try await repository.receive(updated) }
            else { try await repository.save(updated) }
            playlist = updated
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func play(_ track: MusicTrack) async {
        playingTrackID = track.id
        defer { playingTrackID = nil }
        do {
            try await TrackPlaybackService().play(track, on: platform)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func enrichMissingArtwork() async {
        guard !isEnrichingArtwork, playlist.tracks.contains(where: { $0.artwork.imageURL == nil }) else { return }
        isEnrichingArtwork = true
        defer { isEnrichingArtwork = false }

        var didChange = false
        var enrichedTracks: [MusicTrack] = []
        for track in playlist.tracks {
            guard track.artwork.imageURL == nil else {
                enrichedTracks.append(track)
                continue
            }

            let imageURL: URL?
            switch playlist.sourcePlatform {
            case .spotify:
                imageURL = try? await spotify.artworkURL(for: track)
            case .youtubeMusic:
                imageURL = try? await youtubeMusic.artworkURL(for: track)
            case .appleMusic, .none:
                imageURL = await AppleMusicLibraryService().artworkURL(for: track)
            }
            guard let imageURL else {
                enrichedTracks.append(track)
                continue
            }

            var artwork = track.artwork
            artwork.imageURL = imageURL
            enrichedTracks.append(MusicTrack(
                id: track.id,
                isrc: track.isrc,
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration,
                artwork: artwork
            ))
            didChange = true
        }

        guard didChange else { return }
        let updated = SharedPlaylist(
            id: playlist.id,
            title: playlist.title,
            creator: playlist.creator,
            message: playlist.message,
            tracks: enrichedTracks,
            artwork: playlist.artwork,
            createdAt: playlist.createdAt,
            sourceURL: playlist.sourceURL,
            sourcePlatform: playlist.sourcePlatform,
            platformCopies: playlist.platformCopies
        )
        do {
            if isReceived { try await repository.receive(updated) }
            else { try await repository.save(updated) }
            playlist = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
