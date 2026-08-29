import AuthenticationServices
import MusicKit
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
private final class PlatformPlaylistImportViewModel {
    var selectedPlatform: MusicPlatform?
    private(set) var playlists: [SharedPlaylist] = []
    private(set) var isLoading = false
    private(set) var importingID: SharedPlaylist.ID?
    var errorMessage: String?
    var shouldOfferSettings = false

    private let repository: any PlaylistRepository
    private let appleMusic = AppleMusicLibraryService()
    private let spotify = SpotifyLibraryService()
    private let youtubeMusic = YouTubeMusicService()

    init(repository: any PlaylistRepository) { self.repository = repository }

    func select(_ platform: MusicPlatform) async {
        selectedPlatform = platform
        playlists = []
        errorMessage = nil
        shouldOfferSettings = false
        await load()
    }

    func load() async {
        guard let selectedPlatform else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            switch selectedPlatform {
            case .appleMusic:
                let status = await appleMusic.requestAuthorization()
                guard status == .authorized else {
                    shouldOfferSettings = status == .denied || status == .restricted
                    errorMessage = authorizationMessage(for: status)
                    return
                }
                playlists = try await appleMusic.playlists()
            case .spotify:
                playlists = try await spotify.playlists()
            case .youtubeMusic:
                playlists = try await youtubeMusic.playlists()
            }
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
            let nsError = error as NSError
            errorMessage = "\(error.localizedDescription)\n\n오류: \(nsError.domain) (\(nsError.code))"
        }
    }

    private func authorizationMessage(for status: MusicAuthorization.Status) -> String {
        switch status {
        case .denied:
            "Apple Music 접근이 거부되어 있습니다. 설정에서 Munecting의 미디어 및 Apple Music 권한을 허용해주세요."
        case .restricted:
            "이 기기에서는 Apple Music 접근이 제한되어 있습니다. 스크린 타임 또는 기기 관리 설정을 확인해주세요."
        case .notDetermined:
            "Apple Music 접근 권한을 아직 선택하지 않았습니다. 다시 연결해주세요."
        case .authorized:
            ""
        @unknown default:
            "Apple Music 권한 상태를 확인할 수 없습니다."
        }
    }

    func importPlaylist(_ playlist: SharedPlaylist) async -> Bool {
        importingID = playlist.id
        defer { importingID = nil }
        do {
            try await repository.save(playlist)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct PlatformPlaylistImportView: View {
    @State private var viewModel: PlatformPlaylistImportViewModel
    let onImported: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(repository: any PlaylistRepository, onImported: @escaping () -> Void) {
        _viewModel = State(initialValue: PlatformPlaylistImportViewModel(repository: repository))
        self.onImported = onImported
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.selectedPlatform == nil {
                    platformPicker
                } else if viewModel.isLoading {
                    ProgressView("믹스 폴더를 불러오는 중…")
                } else if viewModel.playlists.isEmpty {
                    ContentUnavailableView {
                        Label("가져올 믹스 폴더가 없어요", systemImage: "music.note.list")
                    } description: {
                        Text("선택한 음악 플랫폼의 보관함에 저장된 폴더가 여기에 표시됩니다.")
                    } actions: {
                        Button("다시 연결") { Task { await viewModel.load() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(viewModel.playlists) { playlist in
                        Button {
                            Task {
                                if await viewModel.importPlaylist(playlist) {
                                    onImported()
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack(spacing: 14) {
                                ArtworkView(artwork: playlist.displayArtwork, cornerRadius: 10)
                                    .frame(width: 50, height: 50)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.title)
                                        .font(AppTheme.Typography.rowTitle)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.72)
                                        .truncationMode(.tail)
                                    Text("폴더 안의 노래 \(playlist.tracks.count)곡")
                                        .font(AppTheme.Typography.metadata).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if viewModel.importingID == playlist.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: "plus.circle.fill").foregroundStyle(AppTheme.accent)
                                }
                            }
                        }
                        .disabled(viewModel.importingID != nil)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
            .navigationTitle(viewModel.selectedPlatform.map { "\($0.displayName)에서 가져오기" } ?? "음악 플랫폼에서 가져오기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .alert("음악 플랫폼을 연결하지 못했어요", isPresented: errorBinding) {
                if viewModel.shouldOfferSettings {
                    Button("설정 열기") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Button("확인") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var platformPicker: some View {
        VStack(spacing: 16) {
            Text("가져올 음악 플랫폼을 선택하세요")
                .font(.headline)
            ForEach(MusicPlatform.allCases) { platform in
                Button {
                    Task { await viewModel.select(platform) }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: platform.symbol)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(platform.tint)
                            .frame(width: 34)
                        Text(platform.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}
