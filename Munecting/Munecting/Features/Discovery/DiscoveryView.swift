import SwiftUI
import Combine

@MainActor
final class DiscoveryViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var tracks: [MusicTrack] = []
    private let catalog: any MusicCatalogRepository
    init(catalog: any MusicCatalogRepository) { self.catalog = catalog }
    func load() async { tracks = (try? await catalog.trendingTracks()) ?? [] }
    func search() async { tracks = (try? await catalog.search(query: query)) ?? [] }
}

struct DiscoveryView: View {
    @StateObject private var viewModel: DiscoveryViewModel
    let onPlay: (MusicTrack) -> Void

    init(viewModel: @autoclosure @escaping () -> DiscoveryViewModel, onPlay: @escaping (MusicTrack) -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel()); self.onPlay = onPlay
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TextField("곡, 아티스트, 앨범 검색", text: $viewModel.query).padding(15).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16)).onSubmit { Task { await viewModel.search() } }
                    Text("지금 많이 공유하는 음악").font(.title3.bold())
                    ForEach(Array(viewModel.tracks.enumerated()), id: \.element.id) { index, track in TrackRow(track: track, index: index + 1, accessory: .add) { onPlay(track) } }
                }.padding(20)
            }.navigationTitle("둘러보기").background(AppTheme.background)
        }.task { await viewModel.load() }
    }
}
