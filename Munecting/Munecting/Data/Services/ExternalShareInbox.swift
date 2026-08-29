import Foundation

struct SharedPlaylistLink: Codable, Identifiable, Sendable {
    let id: UUID
    let url: URL
    let sharedAt: Date
    let title: String?
    let message: String?
}

enum ExternalShareInbox {
    static let appGroupIdentifier = "group.sun.Munecting"
    private static let queueKey = "pendingPlaylistLinks"

    static func drain() -> [SharedPlaylistLink] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: queueKey),
              let links = try? JSONDecoder().decode([SharedPlaylistLink].self, from: data)
        else { return [] }

        defaults.removeObject(forKey: queueKey)
        return links
    }
}

extension SharedPlaylistLink {
    var platform: MusicPlatform? {
        let host = url.host()?.lowercased() ?? ""
        if host.contains("music.apple.com") { return .appleMusic }
        if host.contains("spotify.com") { return .spotify }
        if host.contains("youtube.com") || host.contains("youtu.be") { return .youtubeMusic }
        return nil
    }

    func unresolvedPlaylist() -> SharedPlaylist {
        return SharedPlaylist(
            id: "external-\(id.uuidString)",
            title: resolvedTitle,
            creator: AppDefaults.currentUser,
            message: message,
            tracks: [],
            artwork: artwork,
            createdAt: sharedAt,
            sourceURL: url,
            sourcePlatform: platform
        )
    }

    private var resolvedTitle: String {
        if let title = normalized(title), !looksLikeURL(title) { return title }

        if platform == .appleMusic {
            let components = url.pathComponents.filter { $0 != "/" }
            if let playlistMarker = components.lastIndex(where: { $0.hasPrefix("pl.") }), playlistMarker > 0 {
                let slug = components[playlistMarker - 1]
                let decoded = slug.removingPercentEncoding ?? slug
                let readable = decoded.replacingOccurrences(of: "-", with: " ")
                if let title = normalized(readable), title.lowercased() != "playlist" { return title }
            }
        }
        return "새 믹스 폴더"
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func looksLikeURL(_ value: String) -> Bool {
        value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://")
    }

    private var artwork: ArtworkStyle {
        switch platform {
        case .appleMusic:
            ArtworkStyle(primary: .init(red: 0.95, green: 0.18, blue: 0.35), secondary: .init(red: 0.60, green: 0.16, blue: 0.72), symbol: "music.note")
        case .spotify:
            ArtworkStyle(primary: .init(red: 0.12, green: 0.72, blue: 0.35), secondary: .init(red: 0.05, green: 0.25, blue: 0.12), symbol: "waveform")
        case .youtubeMusic:
            AppDefaults.youtubeMusicArtwork
        case nil:
            ArtworkStyle(primary: .init(red: 0.30, green: 0.30, blue: 0.38), secondary: .init(red: 0.12, green: 0.12, blue: 0.16), symbol: "link")
        }
    }
}
