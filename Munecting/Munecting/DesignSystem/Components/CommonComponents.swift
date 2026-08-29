import SwiftUI

struct TrackRow: View {
    let track: MusicTrack
    let index: Int
    var accessory: Accessory = .menu
    let onTap: () -> Void

    enum Accessory { case add, select(Bool), menu }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ArtworkView(artwork: track.artwork, cornerRadius: 10)
                    .frame(width: 46, height: 46)
                    .overlay(Text("\(index)").font(.caption.bold()))
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).font(AppTheme.Typography.rowTitle).lineLimit(1).minimumScaleFactor(0.85)
                    Text("\(track.artist) · \(track.formattedDuration)").font(AppTheme.Typography.metadata).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                accessoryImage
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var accessoryImage: some View {
        switch accessory {
        case .add: Image(systemName: "plus")
        case .menu: Image(systemName: "ellipsis")
        case .select(let selected): Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle").foregroundStyle(selected ? AppTheme.accent : .secondary)
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 38)).foregroundStyle(.secondary)
            Text(title).font(AppTheme.Typography.sectionTitle)
            Text(message).font(AppTheme.Typography.metadata).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 32)
    }
}
