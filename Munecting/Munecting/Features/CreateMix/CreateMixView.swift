import SwiftUI
import Combine

@MainActor
final class CreateMixViewModel: ObservableObject {
    @Published var title = ""
    @Published var message = ""
    @Published private(set) var tracks: [MusicTrack] = []
    @Published var selectedTrackIDs: Set<MusicTrack.ID> = []
    @Published private(set) var isSaving = false

    private let catalog: any MusicCatalogRepository
    private let playlists: any PlaylistRepository

    init(catalog: any MusicCatalogRepository, playlists: any PlaylistRepository) {
        self.catalog = catalog
        self.playlists = playlists
    }

    var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && !selectedTrackIDs.isEmpty && !isSaving }

    func load() async { tracks = (try? await catalog.trendingTracks()) ?? [] }
    func toggle(_ id: MusicTrack.ID) {
        if selectedTrackIDs.contains(id) { selectedTrackIDs.remove(id) } else { selectedTrackIDs.insert(id) }
    }

    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        let selected = tracks.filter { selectedTrackIDs.contains($0.id) }
        let playlist = SharedPlaylist(
            id: UUID().uuidString, title: title, creator: AppDefaults.currentUser,
            message: message.isEmpty ? nil : message, tracks: selected,
            artwork: selected.first?.artwork ?? AppDefaults.defaultArtwork, createdAt: .now
        )
        do { try await playlists.save(playlist); return true } catch { return false }
    }
}

struct CreateMixView: View {
    @StateObject private var viewModel: CreateMixViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: @autoclosure @escaping () -> CreateMixViewModel) { _viewModel = StateObject(wrappedValue: viewModel()) }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        TextField("믹스 제목", text: $viewModel.title).font(.headline).padding(15).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                        TextField("함께 보낼 메시지 (선택)", text: $viewModel.message).font(.subheadline).padding(14).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                        Text("최근 들은 곡").font(AppTheme.Typography.sectionTitle)
                        ForEach(Array(viewModel.tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track, index: index + 1, accessory: .select(viewModel.selectedTrackIDs.contains(track.id))) { viewModel.toggle(track.id) }
                        }
                    }.padding(16).padding(.bottom, 82)
                }
                Button("\(viewModel.selectedTrackIDs.count)곡으로 믹스 만들기") {
                    Task { if await viewModel.save() { dismiss() } }
                }.disabled(!viewModel.canSave).buttonStyle(PrimaryActionButtonStyle()).opacity(viewModel.canSave ? 1 : 0.45).padding(16)
            }
            .navigationTitle("새 믹스").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("취소") { dismiss() } } }
        }.task { await viewModel.load() }
    }
}
