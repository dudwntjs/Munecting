import Foundation
import SwiftData

@ModelActor
actor SwiftDataPlaylistRepository: PlaylistRepository {
    func receivedPlaylists() async throws -> [SharedPlaylist] {
        try fetch(collection: .received)
    }

    func savedPlaylists() async throws -> [SharedPlaylist] {
        try fetch(collection: .owned)
    }

    func save(_ playlist: SharedPlaylist) async throws {
        try upsert(playlist, collection: .owned)
    }

    func receive(_ playlist: SharedPlaylist) async throws {
        try upsert(playlist, collection: .received)
    }

    func delete(id: SharedPlaylist.ID) async throws {
        try delete(id: id, collection: .owned)
    }

    func deleteReceived(id: SharedPlaylist.ID) async throws {
        try delete(id: id, collection: .received)
    }

    private func delete(id: SharedPlaylist.ID, collection: PlaylistCollection) throws {
        let storageID = "\(collection.rawValue):\(id)"
        let descriptor = FetchDescriptor<PlaylistRecord>(
            predicate: #Predicate { $0.storageID == storageID }
        )
        for record in try modelContext.fetch(descriptor) {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    private func fetch(collection: PlaylistCollection) throws -> [SharedPlaylist] {
        try removeLegacySampleData()
        let collectionRawValue = collection.rawValue
        let descriptor = FetchDescriptor<PlaylistRecord>(
            predicate: #Predicate { $0.collectionRawValue == collectionRawValue },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { $0.domainModel() }
    }

    private func removeLegacySampleData() throws {
        let legacyIDs: Set<String> = [
            "playlist-night-us",
            "appleMusic-liked", "appleMusic-night",
            "spotify-liked", "spotify-night"
        ]
        let records = try modelContext.fetch(FetchDescriptor<PlaylistRecord>())
        let samples = records.filter { legacyIDs.contains($0.playlistID) }
        guard !samples.isEmpty else { return }
        samples.forEach(modelContext.delete)
        try modelContext.save()
    }

    private func upsert(_ playlist: SharedPlaylist, collection: PlaylistCollection) throws {
        let storageID = "\(collection.rawValue):\(playlist.id)"
        let descriptor = FetchDescriptor<PlaylistRecord>(
            predicate: #Predicate { $0.storageID == storageID }
        )
        for existing in try modelContext.fetch(descriptor) {
            modelContext.delete(existing)
        }
        modelContext.insert(PlaylistRecord(playlist: playlist, collection: collection))
        try modelContext.save()
    }
}
