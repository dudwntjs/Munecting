import SwiftUI
import Observation
import UIKit

@MainActor
@Observable
final class LibraryViewModel {
    private(set) var playlists: [SharedPlaylist] = []
    var editingPlaylist: SharedPlaylist?
    var errorMessage: String?
    private let repository: any PlaylistRepository

    init(playlists: any PlaylistRepository) { repository = playlists }

    func load() async {
        playlists = (try? await repository.savedPlaylists()) ?? []
    }

    func update(_ playlist: SharedPlaylist, title: String, message: String?, artwork: ArtworkStyle) async -> Bool {
        let updated = SharedPlaylist(
            id: playlist.id, title: title, creator: playlist.creator,
            message: message, tracks: playlist.tracks,
            artwork: artwork, createdAt: playlist.createdAt,
            sourceURL: playlist.sourceURL, sourcePlatform: playlist.sourcePlatform,
            platformCopies: playlist.platformCopies
        )
        do {
            try await repository.save(updated)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ playlist: SharedPlaylist) async {
        do {
            try await repository.delete(id: playlist.id)
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

}

struct LibraryView: View {
    @State private var viewModel: LibraryViewModel
    let refreshID: Int
    let onImport: () -> Void
    let onOpenPlaylist: (SharedPlaylist) -> Void

    init(viewModel: LibraryViewModel, refreshID: Int, onImport: @escaping () -> Void, onOpenPlaylist: @escaping (SharedPlaylist) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.refreshID = refreshID
        self.onImport = onImport
        self.onOpenPlaylist = onOpenPlaylist
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.playlists.isEmpty {
                    VStack(spacing: 22) {
                        EmptyStateView(
                            symbol: "square.stack.3d.up.slash",
                            title: "아직 내 믹스가 없어요",
                            message: "사용 중인 음악 플랫폼에서\n친구에게 보낼 믹스를 가져와 보세요."
                        )
                        Button(action: onImport) {
                            Label("음악 플랫폼에서 가져오기", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .padding(.horizontal, 32)
                    }
                } else {
                    List {
                        ForEach(viewModel.playlists) { playlist in
                            HStack(spacing: 12) {
                                Button { onOpenPlaylist(playlist) } label: {
                                    MyMixRow(playlist: playlist)
                                }
                                .buttonStyle(.plain)

                                ShareLink(
                                    item: MixTransferLink.make(for: playlist),
                                    preview: SharePreview(playlist.title)
                                ) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "airplayaudio")
                                            .font(.subheadline.weight(.semibold))
                                        Text("보내기")
                                            .font(.caption2.weight(.semibold))
                                    }
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 48)
                                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(playlist.title) Munecting으로 보내기")
                            }
                            .listRowBackground(AppTheme.surface)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { Task { await viewModel.delete(playlist) } } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                                Button { viewModel.editingPlaylist = playlist } label: {
                                    Label("수정", systemImage: "pencil")
                                }.tint(.blue)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AppTheme.background)
            .navigationTitle("내 믹스")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onImport) {
                        Label("음원 가져오기", systemImage: "plus")
                    }
                }
            }
        }
        .task(id: refreshID) { await viewModel.load() }
        .sheet(item: $viewModel.editingPlaylist) { playlist in
            EditMixView(playlist: playlist) { title, message, artwork in
                await viewModel.update(playlist, title: title, message: message, artwork: artwork)
            }
        }
        .alert("작업을 완료하지 못했어요", isPresented: errorBinding) {
            Button("확인") { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
    }

}

private struct MyMixRow: View {
    let playlist: SharedPlaylist
    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(artwork: playlist.displayArtwork, cornerRadius: 12).frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 5) {
                Text(playlist.title)
                    .font(AppTheme.Typography.rowTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .truncationMode(.tail)
                Text("\(playlist.tracks.count)곡 · \(playlist.durationInMinutes)분")
                    .font(AppTheme.Typography.metadata).foregroundStyle(.secondary)
                if let message = playlist.message, !message.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "quote.opening")
                            .imageScale(.small)
                        Text(message)
                            .lineLimit(2)
                    }
                        .font(AppTheme.Typography.message)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }
}

struct EditMixView: View {
    let playlist: SharedPlaylist
    let onSave: (String, String?, ArtworkStyle) async -> Bool
    @State private var title: String
    @State private var message: String
    @State private var isSaving = false
    @State private var usesCustomArtwork: Bool
    @State private var primaryColor: Color
    @State private var secondaryColor: Color
    @State private var selectedSymbol: String
    @Environment(\.dismiss) private var dismiss

    init(playlist: SharedPlaylist, onSave: @escaping (String, String?, ArtworkStyle) async -> Bool) {
        self.playlist = playlist
        self.onSave = onSave
        _title = State(initialValue: playlist.title)
        _message = State(initialValue: playlist.message ?? "")
        _usesCustomArtwork = State(initialValue: playlist.artwork.isCustom)
        _primaryColor = State(initialValue: playlist.artwork.primary.color)
        _secondaryColor = State(initialValue: playlist.artwork.secondary.color)
        _selectedSymbol = State(initialValue: Self.customSymbols.contains(playlist.artwork.symbol) ? playlist.artwork.symbol : "music.note")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("믹스 정보") {
                    TextField("믹스 이름", text: $title)
                }
                Section {
                    TextField("친구에게 보낼 멘트", text: $message, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("공유 멘트")
                } footer: {
                    Text("에어드롭으로 믹스를 받은 친구의 홈과 상세 화면에 표시됩니다.")
                }
                Section {
                    Toggle("커스텀 표지 사용", isOn: $usesCustomArtwork)
                    if usesCustomArtwork {
                        HStack(spacing: 16) {
                            ArtworkView(artwork: customArtwork, cornerRadius: 12)
                                .frame(width: 64, height: 64)
                            VStack(spacing: 10) {
                                ColorPicker("첫 번째 색상", selection: $primaryColor, supportsOpacity: false)
                                ColorPicker("두 번째 색상", selection: $secondaryColor, supportsOpacity: false)
                            }
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                            ForEach(Self.customSymbols, id: \.self) { symbol in
                                Button {
                                    selectedSymbol = symbol
                                } label: {
                                    Image(systemName: symbol)
                                        .font(.title3)
                                        .foregroundStyle(selectedSymbol == symbol ? .white : .secondary)
                                        .frame(maxWidth: .infinity, minHeight: 40)
                                        .background(
                                            selectedSymbol == symbol ? AppTheme.accent : AppTheme.surface,
                                            in: RoundedRectangle(cornerRadius: 10)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("표지 아이콘 선택")
                            }
                        }
                    }
                } header: {
                    Text("폴더 썸네일")
                } footer: {
                    Text("음악 플랫폼의 이미지가 보이지 않을 때 원하는 색상으로 표지를 만들 수 있어요.")
                }
            }
                .navigationTitle("믹스 수정")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") {
                            Task {
                                isSaving = true
                                let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
                                let didSave = await onSave(
                                    title.trimmingCharacters(in: .whitespacesAndNewlines),
                                    normalizedMessage.isEmpty ? nil : normalizedMessage,
                                    usesCustomArtwork ? customArtwork : playlist.artwork
                                )
                                isSaving = false
                                if didSave { dismiss() }
                            }
                        }
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    }
                }
                .interactiveDismissDisabled(isSaving)
        }.presentationDetents([.medium])
    }

    private var customArtwork: ArtworkStyle {
        ArtworkStyle(
            primary: rgbColor(from: primaryColor),
            secondary: rgbColor(from: secondaryColor),
            symbol: selectedSymbol,
            imageURL: nil,
            isCustom: true
        )
    }

    private static let customSymbols = [
        "music.note", "music.note.list", "headphones", "waveform", "guitars",
        "heart.fill", "sparkles", "moon.stars.fill", "sun.max.fill", "cloud.rain.fill"
    ]

    private func rgbColor(from color: Color) -> RGBColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return RGBColor(red: Double(red), green: Double(green), blue: Double(blue))
    }
}
