import Foundation

enum MixTransferImporter {
    static func decode(from url: URL) throws -> SharedPlaylist {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()

        if let playlist = try? decoder.decode(SharedPlaylist.self, from: data) {
            return playlist
        }
        if let envelope = try? decoder.decode(MixJSONEnvelope.self, from: data) {
            return envelope.playlist
        }
        throw MixTransferError.invalidJSON
    }
}

enum MixTransferLink {
    static func make(for playlist: SharedPlaylist) -> URL {
        let data = (try? JSONEncoder().encode(playlist)) ?? Data()
        let payload = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var components = URLComponents()
        components.scheme = "munecting"
        components.host = "receive"
        components.queryItems = [URLQueryItem(name: "payload", value: payload)]
        return components.url!
    }

    static func decode(from url: URL) throws -> SharedPlaylist {
        guard url.scheme == "munecting", url.host == "receive",
              let payload = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "payload" })?.value
        else { throw MixTransferError.invalidJSON }

        var base64 = payload.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: base64) else { throw MixTransferError.invalidJSON }
        return try JSONDecoder().decode(SharedPlaylist.self, from: data)
    }
}

private struct MixJSONEnvelope: Decodable {
    let playlist: SharedPlaylist
}

private enum MixTransferError: LocalizedError {
    case invalidJSON

    var errorDescription: String? {
        "Munecting 믹스 정보가 담긴 JSON 파일이 아닙니다."
    }
}
