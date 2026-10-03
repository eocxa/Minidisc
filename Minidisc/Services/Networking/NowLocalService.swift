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
    let adlibIsBefore: Bool?

    enum CodingKeys: String, CodingKey {
        case time
        case endTime
        case text
        case words
        case agent
        case hasAdlib = "has_adlib"
        case main
        case adlib
        case adlibIsBefore = "adlib_is_before"
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

private nonisolated final class EnrichmentCacheStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: NowLocalEnrichment]

    nonisolated init() {
        self.cache = Self.loadFromDisk()
    }

    private static var cacheFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("nowlocal_enrichment_cache.json")
    }

    nonisolated private static func loadFromDisk() -> [String: NowLocalEnrichment] {
        guard let url = cacheFileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: NowLocalEnrichment].self, from: data) else {
            return [:]
        }
        return decoded
    }

    nonisolated private func saveToDisk(_ snapshot: [String: NowLocalEnrichment]) {
        guard let url = Self.cacheFileURL else { return }
        Task.detached(priority: .background) {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: [.atomic])
            }
        }
    }

    nonisolated func get(album: String?, artist: String?, title: String? = nil) -> NowLocalEnrichment? {
        let alb = (album ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let art = (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tit = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trackKey = "\(alb)_\(art)_\(tit)"
        let albumKey = "\(alb)_\(art)_"
        let albumOnlyKey = "\(alb)__"

        lock.lock()
        defer { lock.unlock() }

        if !tit.isEmpty, let exact = cache[trackKey] {
            return exact
        }
        if let albumEnrichment = cache[albumKey] {
            return albumEnrichment
        }
        if let albumOnly = cache[albumOnlyKey] {
            return albumOnly
        }
        return nil
    }

    nonisolated func store(_ enrichment: NowLocalEnrichment, forKeys keys: [String]) {
        lock.lock()
        for k in keys {
            cache[k.lowercased()] = enrichment
        }
        let snapshot = cache
        lock.unlock()
        saveToDisk(snapshot)
    }
}

actor NowLocalService {
    static let shared = NowLocalService()
    nonisolated private static let storage = EnrichmentCacheStorage()

    private var cache: [String: NowLocalEnrichment] = [:]
    private var lyricsCache: [String: NowLocalLyricsResponse] = [:]
    private let logger = Logger(subsystem: "app.minidisc.nowlocal", category: "Enrichment")

    nonisolated func cachedEnrichment(album: String?, artist: String?, title: String? = nil) -> NowLocalEnrichment? {
        Self.storage.get(album: album, artist: artist, title: title)
    }

    nonisolated func storeCachedEnrichment(_ enrichment: NowLocalEnrichment, forKeys keys: [String]) {
        Self.storage.store(enrichment, forKeys: keys)
    }

    nonisolated func resolveCandidateBaseURLs(activeServerBaseURL: String?) -> [URL] {
        var urls: [URL] = []
        if let custom = UserDefaults.standard.string(forKey: "minidisc_nowlocal_url"),
           !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let customURL = URL(string: custom) {
            urls.append(customURL)
        }
        if let active = activeServerBaseURL, let parsed = URL(string: active) {
            if let host = parsed.host {
                let scheme = parsed.scheme ?? "http"
                if let u7430 = URL(string: "\(scheme)://\(host):7430"), !urls.contains(u7430) {
                    urls.append(u7430)
                }
                if let u8000 = URL(string: "\(scheme)://\(host):8000"), !urls.contains(u8000) {
                    urls.append(u8000)
                }
            }
            if !urls.contains(parsed) {
                urls.append(parsed)
            }
        }
        return urls
    }

    nonisolated func resolveServerBaseURL(activeServerBaseURL: String?) -> URL? {
        resolveCandidateBaseURLs(activeServerBaseURL: activeServerBaseURL).first
    }

    nonisolated func resolveArtworkURL(path: String?, activeServerBaseURL: String?) -> URL? {
        guard let path = path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        for base in resolveCandidateBaseURLs(activeServerBaseURL: activeServerBaseURL) {
            if let resolved = URL(string: path, relativeTo: base)?.absoluteURL {
                return resolved
            }
        }
        return nil
    }

    private func cleanMetadata(_ string: String) -> String {
        var result = string
        let patterns = [
            "\\s*\\(.*?remaster.*?\\)",
            "\\s*\\[.*?remaster.*?\\]",
            "\\s*\\(.*?deluxe.*?\\)",
            "\\s*\\[.*?deluxe.*?\\]",
            "\\s*\\(.*?bonus.*?\\)",
            "\\s*\\[.*?bonus.*?\\]",
            "\\s*\\(.*?version.*?\\)",
            "\\s*\\[.*?version.*?\\]",
            "\\s*\\(.*?edition.*?\\)",
            "\\s*\\[.*?edition.*?\\]",
            "\\s*\\(.*?explicit.*?\\)",
            "\\s*\\[.*?explicit.*?\\]"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func performEnrichmentRequest(base: URL, album: String?, artist: String?, title: String?, cacheKey: String) async -> NowLocalEnrichment? {
        var components = URLComponents(url: base.appendingPathComponent("api/enrichment"), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []
        if let album, !album.isEmpty { queryItems.append(URLQueryItem(name: "album", value: album)) }
        if let artist, !artist.isEmpty { queryItems.append(URLQueryItem(name: "artist", value: artist)) }
        if let title, !title.isEmpty { queryItems.append(URLQueryItem(name: "title", value: title)) }
        components?.queryItems = queryItems

        guard let requestURL = components?.url else { return nil }

        do {
            var request = URLRequest(url: requestURL)
            request.timeoutInterval = 3.0
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoder = JSONDecoder()
            let enrichment = try decoder.decode(NowLocalEnrichment.self, from: data)
            if enrichment.found {
                cache[cacheKey] = enrichment
                storeCachedEnrichment(enrichment, forKeys: [cacheKey, "\(album ?? "")_\(artist ?? "")_"])
                return enrichment
            }
        } catch {
            logger.debug("Enrichment lookup failed for \(cacheKey): \(error.localizedDescription)")
        }
        return nil
    }

    private func performLibraryLookup(base: URL, album: String?, artist: String?, title: String?) async -> NowLocalEnrichment? {
        let libraryURL = base.appendingPathComponent("api/library")
        do {
            var request = URLRequest(url: libraryURL)
            request.timeoutInterval = 3.0
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tracks = json["tracks"] as? [[String: Any]] else { return nil }

            let albQ = (album ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let artQ = (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let titQ = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            var bestTrack: [String: Any]?
            for t in tracks {
                let tAlb = (t["album"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let tArt = (t["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let tTit = (t["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

                if !titQ.isEmpty && tTit == titQ && (artQ.isEmpty || tArt.contains(artQ) || artQ.contains(tArt)) {
                    bestTrack = t
                    break
                }
                if !albQ.isEmpty && tAlb == albQ && (artQ.isEmpty || tArt.contains(artQ) || artQ.contains(tArt)) {
                    bestTrack = t
                    if titQ.isEmpty { break }
                }
                if !albQ.isEmpty && tAlb == albQ && bestTrack == nil {
                    bestTrack = t
                }
            }

            guard let track = bestTrack else { return nil }
            let tall = track["animated_tall_url"] as? String
            let square = track["animated_square_url"] as? String
            guard tall != nil || square != nil else { return nil }

            return NowLocalEnrichment(
                found: true,
                trackId: track["id"] as? String,
                title: track["title"] as? String,
                artist: track["artist"] as? String,
                album: track["album"] as? String,
                hasAnimatedArtwork: (track["has_animated_artwork"] as? Bool) ?? true,
                animatedSquareUrl: square,
                animatedTallUrl: tall,
                isAtmos: track["is_atmos"] as? Bool,
                isLossless: track["is_lossless"] as? Bool,
                lyricsUrl: (track["lyrics_type"] as? String != "none") ? "/api/lyrics/\(track["id"] ?? "")" : nil,
                lyricsType: track["lyrics_type"] as? String
            )
        } catch {
            return nil
        }
    }

    func fetchEnrichment(album: String?, artist: String?, title: String? = nil, activeServerBaseURL: String?) async -> NowLocalEnrichment? {
        guard !UserDefaults.standard.bool(forKey: "minidisc_nowlocal_disabled") else { return nil }
        let candidates = resolveCandidateBaseURLs(activeServerBaseURL: activeServerBaseURL)
        guard !candidates.isEmpty else { return nil }

        let cacheKey = "\(album ?? "")_\(artist ?? "")_\(title ?? "")"
        if let cached = cache[cacheKey] {
            return cached
        }
        if let fastCached = cachedEnrichment(album: album, artist: artist, title: title) {
            cache[cacheKey] = fastCached
            return fastCached
        }

        for base in candidates {
            if let result = await performEnrichmentRequest(base: base, album: album, artist: artist, title: title, cacheKey: cacheKey) {
                storeCachedEnrichment(result, forKeys: [cacheKey, "\(album ?? "")_\(artist ?? "")_"])
                return result
            }
        }

        // Retry with cleaned metadata if raw strings had common tags
        let cleanAlbum = album.map { cleanMetadata($0) }
        let cleanArtist = artist.map { cleanMetadata($0) }
        let cleanTitle = title.map { cleanMetadata($0) }

        if (cleanAlbum != album || cleanArtist != artist || cleanTitle != title) {
            let cleanKey = "\(cleanAlbum ?? "")_\(cleanArtist ?? "")_\(cleanTitle ?? "")"
            if let cachedClean = cache[cleanKey] {
                cache[cacheKey] = cachedClean
                storeCachedEnrichment(cachedClean, forKeys: [cacheKey, cleanKey, "\(cleanAlbum ?? "")_\(cleanArtist ?? "")_"])
                return cachedClean
            }
            for base in candidates {
                if let cleanResult = await performEnrichmentRequest(base: base, album: cleanAlbum, artist: cleanArtist, title: cleanTitle, cacheKey: cleanKey) {
                    cache[cacheKey] = cleanResult
                    storeCachedEnrichment(cleanResult, forKeys: [cacheKey, cleanKey, "\(cleanAlbum ?? "")_\(cleanArtist ?? "")_"])
                    return cleanResult
                }
            }
        }

        // Fallback: check /api/library on each candidate
        for base in candidates {
            if let libResult = await performLibraryLookup(base: base, album: album, artist: artist, title: title) {
                cache[cacheKey] = libResult
                storeCachedEnrichment(libResult, forKeys: [cacheKey, "\(album ?? "")_\(artist ?? "")_"])
                return libResult
            }
        }

        return nil
    }

    func fetchLyrics(pathOrTrackId: String, activeServerBaseURL: String?) async -> NowLocalLyricsResponse? {
        if let cached = lyricsCache[pathOrTrackId] {
            return cached
        }

        if pathOrTrackId.hasPrefix("http://") || pathOrTrackId.hasPrefix("https://"),
           let fullURL = URL(string: pathOrTrackId) {
            return await performLyricsFetch(url: fullURL, cacheKey: pathOrTrackId)
        }

        let candidates = resolveCandidateBaseURLs(activeServerBaseURL: activeServerBaseURL)
        guard !candidates.isEmpty else { return nil }

        for base in candidates {
            let fullURL: URL?
            if pathOrTrackId.hasPrefix("/api/lyrics/") {
                fullURL = URL(string: pathOrTrackId, relativeTo: base)?.absoluteURL
            } else {
                let sanitized = pathOrTrackId.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                fullURL = URL(string: "/api/lyrics/\(sanitized)", relativeTo: base)?.absoluteURL
            }

            guard let requestURL = fullURL else { continue }
            if let result = await performLyricsFetch(url: requestURL, cacheKey: pathOrTrackId) {
                return result
            }
        }
        return nil
    }

    private func performLyricsFetch(url: URL, cacheKey: String) async -> NowLocalLyricsResponse? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoder = JSONDecoder()
            let lyricsResponse = try decoder.decode(NowLocalLyricsResponse.self, from: data)
            lyricsCache[cacheKey] = lyricsResponse
            return lyricsResponse
        } catch {
            logger.debug("Lyrics lookup failed for \(url): \(error.localizedDescription)")
            return nil
        }
    }
}
