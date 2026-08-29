import Foundation
import SwiftData

enum PlaylistCollection: String, Codable, Sendable {
    case received
    case owned
}

@Model
final class PlaylistRecord {
    @Attribute(.unique) var storageID: String
    var playlistID: String
    var collectionRawValue: String
    var title: String
    var creatorID: String
    var creatorDisplayName: String
    var creatorAvatarInitial: String
    var message: String?
    var createdAt: Date
    var sourceURLString: String?
    var sourcePlatformRawValue: String?
    var appleMusicCopyURLString: String?
    var spotifyCopyURLString: String?
    var youtubeMusicCopyURLString: String?
    var artworkPrimaryRed: Double
    var artworkPrimaryGreen: Double
    var artworkPrimaryBlue: Double
    var artworkSecondaryRed: Double
    var artworkSecondaryGreen: Double
    var artworkSecondaryBlue: Double
    var artworkSymbol: String
    var artworkImageURLString: String?
    var artworkIsCustom: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \TrackRecord.playlist)
    var tracks: [TrackRecord]

    init(playlist: SharedPlaylist, collection: PlaylistCollection) {
        storageID = "\(collection.rawValue):\(playlist.id)"
        playlistID = playlist.id
        collectionRawValue = collection.rawValue
        title = playlist.title
        creatorID = playlist.creator.id
        creatorDisplayName = playlist.creator.displayName
        creatorAvatarInitial = playlist.creator.avatarInitial
        message = playlist.message
        createdAt = playlist.createdAt
        sourceURLString = playlist.sourceURL?.absoluteString
        sourcePlatformRawValue = playlist.sourcePlatform?.rawValue
        appleMusicCopyURLString = playlist.platformCopies[.appleMusic]?.absoluteString
        spotifyCopyURLString = playlist.platformCopies[.spotify]?.absoluteString
        youtubeMusicCopyURLString = playlist.platformCopies[.youtubeMusic]?.absoluteString
        artworkPrimaryRed = playlist.artwork.primary.red
        artworkPrimaryGreen = playlist.artwork.primary.green
        artworkPrimaryBlue = playlist.artwork.primary.blue
        artworkSecondaryRed = playlist.artwork.secondary.red
        artworkSecondaryGreen = playlist.artwork.secondary.green
        artworkSecondaryBlue = playlist.artwork.secondary.blue
        artworkSymbol = playlist.artwork.symbol
        artworkImageURLString = playlist.artwork.imageURL?.absoluteString
        artworkIsCustom = playlist.artwork.isCustom
        tracks = playlist.tracks.enumerated().map { index, track in
            TrackRecord(track: track, order: index)
        }
    }

    func domainModel() -> SharedPlaylist {
        let legacySystemMessages = [
            "곡 정보를 불러오려면 원본 플랫폼을 열어주세요.",
            "곡 정보를 불러오려면 원본 플랫폼을 열어주세요"
        ]
        let visibleMessage = message.flatMap { legacySystemMessages.contains($0) ? nil : $0 }
        return SharedPlaylist(
            id: playlistID,
            title: title,
            creator: UserSummary(
                id: creatorID,
                displayName: creatorDisplayName,
                avatarInitial: creatorAvatarInitial
            ),
            message: visibleMessage,
            tracks: tracks.sorted { $0.order < $1.order }.map { $0.domainModel() },
            artwork: ArtworkStyle(
                primary: RGBColor(red: artworkPrimaryRed, green: artworkPrimaryGreen, blue: artworkPrimaryBlue),
                secondary: RGBColor(red: artworkSecondaryRed, green: artworkSecondaryGreen, blue: artworkSecondaryBlue),
                symbol: artworkSymbol,
                imageURL: artworkImageURLString.flatMap(URL.init(string:)),
                isCustom: artworkIsCustom
            ),
            createdAt: createdAt,
            sourceURL: sourceURLString.flatMap(URL.init(string:)),
            sourcePlatform: sourcePlatformRawValue.flatMap(MusicPlatform.init(rawValue:)),
            platformCopies: platformCopies
        )
    }

    private var platformCopies: [MusicPlatform: URL] {
        var result: [MusicPlatform: URL] = [:]
        if let url = appleMusicCopyURLString.flatMap(URL.init(string:)) { result[.appleMusic] = url }
        if let url = spotifyCopyURLString.flatMap(URL.init(string:)) { result[.spotify] = url }
        if let url = youtubeMusicCopyURLString.flatMap(URL.init(string:)) { result[.youtubeMusic] = url }
        return result
    }
}

@Model
final class TrackRecord {
    var trackID: String
    var order: Int
    var isrc: String?
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var artworkPrimaryRed: Double
    var artworkPrimaryGreen: Double
    var artworkPrimaryBlue: Double
    var artworkSecondaryRed: Double
    var artworkSecondaryGreen: Double
    var artworkSecondaryBlue: Double
    var artworkSymbol: String
    var artworkImageURLString: String?
    var playlist: PlaylistRecord?

    init(track: MusicTrack, order: Int) {
        trackID = track.id
        self.order = order
        isrc = track.isrc
        title = track.title
        artist = track.artist
        album = track.album
        duration = track.duration
        artworkPrimaryRed = track.artwork.primary.red
        artworkPrimaryGreen = track.artwork.primary.green
        artworkPrimaryBlue = track.artwork.primary.blue
        artworkSecondaryRed = track.artwork.secondary.red
        artworkSecondaryGreen = track.artwork.secondary.green
        artworkSecondaryBlue = track.artwork.secondary.blue
        artworkSymbol = track.artwork.symbol
        artworkImageURLString = track.artwork.imageURL?.absoluteString
    }

    func domainModel() -> MusicTrack {
        MusicTrack(
            id: trackID,
            isrc: isrc,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            artwork: ArtworkStyle(
                primary: RGBColor(red: artworkPrimaryRed, green: artworkPrimaryGreen, blue: artworkPrimaryBlue),
                secondary: RGBColor(red: artworkSecondaryRed, green: artworkSecondaryGreen, blue: artworkSecondaryBlue),
                symbol: artworkSymbol,
                imageURL: artworkImageURLString.flatMap(URL.init(string:))
            )
        )
    }
}
