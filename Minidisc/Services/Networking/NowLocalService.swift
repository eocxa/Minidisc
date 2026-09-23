import Foundation
import OSLog

nonisolated struct NowLocalEnrichment: Sendable, Codable {
    let found: Bool
    let trackId: String?
    let title: String?
    let artist: String?
    let album: String?
    let hasAnimatedArtwork: Bool?
    let animatedSquareUrl: String?
    let animatedTallUrl: String?
    let isAtmos: Bool?
    let isLossless: Bool?
    let lyricsUrl: String?
    let lyricsType: String?

    enum CodingKeys: String, CodingKey {
        case found
        case trackId = "track_id"
        case title
        case artist
        case album
        case hasAnimatedArtwork = "has_animated_artwork"
        case animatedSquareUrl = "animated_square_url"
        case animatedTallUrl = "animated_tall_url"
        case isAtmos = "is_atmos"
        case isLossless = "is_lossless"
        case lyricsUrl = "lyrics_url"
        case lyricsType = "lyrics_type"
    }
}

nonisolated struct NowLocalLyricWord: Sendable, Codable, Identifiable, Hashable {
    var id: String { "\(time)_\(text)" }
    let time: Double
    let endTime: Double?
    let text: String

    init(time: Double, endTime: Double?, text: String) {
        self.time = time
        self.endTime = endTime
        self.text = text
    }
}

nonisolated struct NowLocalLyricSubPart: Sendable, Codable, Hashable {
    let text: String?
    let words: [NowLocalLyricWord]?
    let time: Double?
    let endTime: Double?
}

nonisolated struct NowLocalLyricLine: Sendable, Codable, Identifiable, Hashable {
    var id: String { "\(time)_\(text)" }
    let time: Double
    let endTime: Double?
    let text: String
    let words: [NowLocalLyricWord]?
    let agent: String? // "v1" or "v2"
    let hasAdlib: Bool?
    let main: NowLocalLyricSubPart?
    let adlib: NowLocalLyricSubPart?

    enum CodingKeys: String, CodingKey {
        case time
        case endTime
        case text
        case words
        case agent
        case hasAdlib = "has_adlib"
        case main
        case adlib
    }
}

nonisolated struct NowLocalLyricsResponse: Sendable, Codable, Equatable {
    let lyrics: [NowLocalLyricLine]
    let lyricsType: String?
    let hasWordSync: Bool?
    let composer: String?

    enum CodingKeys: String, CodingKey {
        case lyrics
        case lyricsType = "lyrics_type"
        case hasWordSync = "has_word_sync"
        case composer
    }
}

actor NowLocalService {
    static let shared = NowLocalService()
    private var cache: [String: NowLocalEnrichment] = [:]
    private var lyricsCache: [String: NowLocalLyricsResponse] = [:]
    private let logger = Logger(subsystem: "app.minidisc.nowlocal", category: "Enrichment")

    nonisolated func resolveServerBaseURL(activeServerBaseURL: String?) -> URL? {
        if let custom = UserDefaults.standard.string(forKey: "minidisc_nowlocal_url"),
           !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let customURL = URL(string: custom) {
            return customURL
        }
        guard let active = activeServerBaseURL, let parsed = URL(string: active), let host = parsed.host else {
            return nil
        }
        let scheme = parsed.scheme ?? "http"
        return URL(string: "\(scheme)://\(host):7430")
    }

    nonisolated func resolveArtworkURL(path: String?, activeServerBaseURL: String?) -> URL? {
        guard let path = path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        guard let base = resolveServerBaseURL(activeServerBaseURL: activeServerBaseURL) else { return nil }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    func fetchEnrichment(album: String?, artist: String?, title: String? = nil, activeServerBaseURL: String?) async -> NowLocalEnrichment? {
        guard let base = resolveServerBaseURL(activeServerBaseURL: activeServerBaseURL) else { return nil }

        let cacheKey = "\(album ?? "")_\(artist ?? "")_\(title ?? "")"
        if let cached = cache[cacheKey] {
            return cached
        }

        var components = URLComponents(url: base.appendingPathComponent("api/enrichment"), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []
        if let album, !album.isEmpty { queryItems.append(URLQueryItem(name: "album", value: album)) }
        if let artist, !artist.isEmpty { queryItems.append(URLQueryItem(name: "artist", value: artist)) }
        if let title, !title.isEmpty { queryItems.append(URLQueryItem(name: "title", value: title)) }
        components?.queryItems = queryItems

        guard let requestURL = components?.url else { return nil }

        do {
            var request = URLRequest(url: requestURL)
            request.timeoutInterval = 4.0
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoder = JSONDecoder()
            let enrichment = try decoder.decode(NowLocalEnrichment.self, from: data)
            if enrichment.found {
                cache[cacheKey] = enrichment
                return enrichment
            }
        } catch {
            logger.debug("Enrichment lookup failed for \(cacheKey): \(error.localizedDescription)")
        }
        return nil
    }

    func fetchLyrics(pathOrTrackId: String, activeServerBaseURL: String?) async -> NowLocalLyricsResponse? {
        guard let base = resolveServerBaseURL(activeServerBaseURL: activeServerBaseURL) else { return nil }

        if let cached = lyricsCache[pathOrTrackId] {
            return cached
        }

        let fullURL: URL?
        if pathOrTrackId.hasPrefix("http://") || pathOrTrackId.hasPrefix("https://") {
            fullURL = URL(string: pathOrTrackId)
        } else if pathOrTrackId.hasPrefix("/api/lyrics/") {
            fullURL = URL(string: pathOrTrackId, relativeTo: base)?.absoluteURL
        } else {
            fullURL = URL(string: "/api/lyrics/\(pathOrTrackId)", relativeTo: base)?.absoluteURL
        }

        guard let requestURL = fullURL else { return nil }

        do {
            var request = URLRequest(url: requestURL)
            request.timeoutInterval = 5.0
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoder = JSONDecoder()
            let lyricsResponse = try decoder.decode(NowLocalLyricsResponse.self, from: data)
            lyricsCache[pathOrTrackId] = lyricsResponse
            return lyricsResponse
        } catch {
            logger.debug("Lyrics lookup failed for \(pathOrTrackId): \(error.localizedDescription)")
        }
        return nil
    }
}
