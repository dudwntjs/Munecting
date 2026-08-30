import SwiftUI

struct MusicTrack: Identifiable, Hashable, Codable, Sendable {
    typealias ID = String

    let id: ID
    let isrc: String?
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let artwork: ArtworkStyle

    var formattedDuration: String {
        let seconds = Int(duration)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct SharedPlaylist: Identifiable, Hashable, Codable, Sendable {
    typealias ID = String

    let id: ID
    let title: String
    let creator: UserSummary
    let message: String?
    let tracks: [MusicTrack]
    let artwork: ArtworkStyle
    let createdAt: Date
    var sourceURL: URL? = nil
    var sourcePlatform: MusicPlatform? = nil
    var platformCopies: [MusicPlatform: URL] = [:]

    var totalDuration: TimeInterval { tracks.reduce(0) { $0 + $1.duration } }
    var durationInMinutes: Int { max(1, Int(totalDuration / 60)) }
    var displayArtwork: ArtworkStyle {
        if artwork.isCustom { return artwork }
        guard artwork.imageURL == nil,
              let trackArtwork = tracks.first(where: { $0.artwork.imageURL != nil })?.artwork
        else { return artwork }
        return trackArtwork
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, creator, message, tracks, artwork, createdAt
        case sourceURL, sourcePlatform, platformCopies
    }

    init(
        id: ID, title: String, creator: UserSummary, message: String?, tracks: [MusicTrack],
        artwork: ArtworkStyle, createdAt: Date, sourceURL: URL? = nil,
        sourcePlatform: MusicPlatform? = nil, platformCopies: [MusicPlatform: URL] = [:]
    ) {
        self.id = id
        self.title = title
        self.creator = creator
        self.message = message
        self.tracks = tracks
        self.artwork = artwork
        self.createdAt = createdAt
        self.sourceURL = sourceURL
        self.sourcePlatform = sourcePlatform
        self.platformCopies = platformCopies
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(ID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        creator = try values.decode(UserSummary.self, forKey: .creator)
        message = try values.decodeIfPresent(String.self, forKey: .message)
        tracks = try values.decode([MusicTrack].self, forKey: .tracks)
        artwork = try values.decode(ArtworkStyle.self, forKey: .artwork)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        sourceURL = try values.decodeIfPresent(URL.self, forKey: .sourceURL)
        sourcePlatform = try values.decodeIfPresent(MusicPlatform.self, forKey: .sourcePlatform)
        platformCopies = try values.decodeIfPresent([MusicPlatform: URL].self, forKey: .platformCopies) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(title, forKey: .title)
        try values.encode(creator, forKey: .creator)
        try values.encodeIfPresent(message, forKey: .message)
        try values.encode(tracks, forKey: .tracks)
        try values.encode(artwork, forKey: .artwork)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try values.encodeIfPresent(sourcePlatform, forKey: .sourcePlatform)
        try values.encode(platformCopies, forKey: .platformCopies)
    }
}

struct UserSummary: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let displayName: String
    let avatarInitial: String
}

enum MusicPlatform: String, CaseIterable, Identifiable, Codable, Sendable {
    case appleMusic
    case spotify
    case youtubeMusic

    var id: Self { self }
    var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .youtubeMusic: "YouTube Music"
        }
    }
    var symbol: String {
        switch self {
        case .appleMusic: "music.note"
        case .spotify: "waveform"
        case .youtubeMusic: "play.circle.fill"
        }
    }
    var tint: Color {
        switch self {
        case .appleMusic: .pink
        case .spotify: .green
        case .youtubeMusic: .red
        }
    }
}

struct ArtworkStyle: Hashable, Codable, Sendable {
    let primary: RGBColor
    let secondary: RGBColor
    let symbol: String
    var imageURL: URL? = nil
    var isCustom: Bool = false

    var colors: [Color] { [primary.color, secondary.color] }

    private enum CodingKeys: String, CodingKey { case primary, secondary, symbol, imageURL, isCustom }

    init(primary: RGBColor, secondary: RGBColor, symbol: String, imageURL: URL? = nil, isCustom: Bool = false) {
        self.primary = primary
        self.secondary = secondary
        self.symbol = symbol
        self.imageURL = imageURL
        self.isCustom = isCustom
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        primary = try values.decode(RGBColor.self, forKey: .primary)
        secondary = try values.decode(RGBColor.self, forKey: .secondary)
        symbol = try values.decode(String.self, forKey: .symbol)
        imageURL = try values.decodeIfPresent(URL.self, forKey: .imageURL)
        isCustom = try values.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }
}

struct RGBColor: Hashable, Codable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }
}

struct PlaylistImportReceipt: Sendable {
    let platform: MusicPlatform
    let externalPlaylistID: String
    let matchedTrackCount: Int
    let unmatchedTracks: [MusicTrack]
}

enum PlaylistImportError: LocalizedError, Equatable {
    case authenticationRequired(MusicPlatform)
    case noTracksMatched
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .authenticationRequired(let platform): return "\(platform.displayName) 계정 연결이 필요합니다."
        case .noTracksMatched: return "가져올 수 있는 곡을 찾지 못했습니다."
        case .serviceUnavailable: return "음악 서비스에 연결할 수 없습니다."
        }
    }
}
