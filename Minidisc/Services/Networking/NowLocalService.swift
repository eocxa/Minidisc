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
        var sanitized: [String: NowLocalEnrichment] = [:]
        for (k, v) in decoded {
            if k.hasSuffix("_") && v.lyricsUrl != nil {
                sanitized[k] = NowLocalEnrichment(
                    found: v.found,
                    trackId: nil,
                    title: nil,
                    artist: v.artist,
                    album: v.album,
                    hasAnimatedArtwork: v.hasAnimatedArtwork,
                    animatedSquareUrl: v.animatedSquareUrl,
                    animatedTallUrl: v.animatedTallUrl,
                    isAtmos: v.isAtmos,
                    isLossless: v.isLossless,
                    lyricsUrl: nil,
                    lyricsType: nil
                )
            } else {
                sanitized[k] = v
            }
        }
        return sanitized
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

        func stripLyrics(_ e: NowLocalEnrichment) -> NowLocalEnrichment {
            NowLocalEnrichment(
                found: e.found,
                trackId: nil,
                title: nil,
                artist: e.artist,
                album: e.album,
                hasAnimatedArtwork: e.hasAnimatedArtwork,
                animatedSquareUrl: e.animatedSquareUrl,
                animatedTallUrl: e.animatedTallUrl,
                isAtmos: e.isAtmos,
                isLossless: e.isLossless,
                lyricsUrl: nil,
                lyricsType: nil
            )
        }

        func findAlbumEnrichment() -> NowLocalEnrichment? {
            if let exact = cache[albumKey] ?? cache[albumOnlyKey] {
                return exact
            }
            if !alb.isEmpty {
                if let prefixMatch = cache.first(where: { (k, _) in
                    (k.hasPrefix("\(alb)_") && k.hasSuffix("_")) || k == "\(alb)__"
                })?.value {
                    return prefixMatch
                }
                // Check if any track from this album has animated artwork cached
                if let trackWithMotion = cache.first(where: { (k, v) in
                    k.hasPrefix("\(alb)_") && (v.animatedTallUrl != nil || v.animatedSquareUrl != nil)
                })?.value {
                    return stripLyrics(trackWithMotion)
                }
            }
            return nil
        }

        if !tit.isEmpty {
            if let exact = cache[trackKey] {
                // If track is cached without motion artwork, inherit from album if available
                if exact.animatedTallUrl == nil && exact.animatedSquareUrl == nil,
                   let albumEnrichment = findAlbumEnrichment(),
                   albumEnrichment.animatedTallUrl != nil || albumEnrichment.animatedSquareUrl != nil {
                    return NowLocalEnrichment(
                        found: exact.found,
                        trackId: exact.trackId,
                        title: exact.title,
                        artist: exact.artist,
                        album: exact.album,
                        hasAnimatedArtwork: true,
                        animatedSquareUrl: albumEnrichment.animatedSquareUrl,
                        animatedTallUrl: albumEnrichment.animatedTallUrl,
                        isAtmos: exact.isAtmos,
                        isLossless: exact.isLossless,
                        lyricsUrl: exact.lyricsUrl,
                        lyricsType: exact.lyricsType
                    )
                }
                return exact
            }
            if let albumEnrichment = findAlbumEnrichment() {
                return stripLyrics(albumEnrichment)
            }
            return nil
        }

        return findAlbumEnrichment()
    }

    nonisolated func store(_ enrichment: NowLocalEnrichment, forKeys keys: [String]) {
        lock.lock()
        for k in keys {
            if k.hasSuffix("_") {
                // Strip song-specific lyrics from album-wide keys so they never leak to other tracks
                let albumLevel = NowLocalEnrichment(
                    found: enrichment.found,
                    trackId: nil,
                    title: nil,
                    artist: enrichment.artist,
                    album: enrichment.album,
                    hasAnimatedArtwork: enrichment.hasAnimatedArtwork,
                    animatedSquareUrl: enrichment.animatedSquareUrl,
                    animatedTallUrl: enrichment.animatedTallUrl,
                    isAtmos: enrichment.isAtmos,
                    isLossless: enrichment.isLossless,
                    lyricsUrl: nil,
                    lyricsType: nil
                )
                cache[k.lowercased()] = albumLevel
                let parts = k.lowercased().split(separator: "_", omittingEmptySubsequences: false)
                if let first = parts.first, !first.isEmpty {
                    cache["\(first)__"] = albumLevel
                }
            } else {
                cache[k.lowercased()] = enrichment
                if enrichment.animatedTallUrl != nil || enrichment.animatedSquareUrl != nil {
                    // Propagate motion artwork to the album level keys so all tracks & album detail benefit
                    let parts = k.lowercased().split(separator: "_", omittingEmptySubsequences: false)
                    if parts.count >= 2, let first = parts.first, !first.isEmpty {
                        let second = parts[1]
                        let albKey = "\(first)_\(second)_"
                        let albOnlyKey = "\(first)__"
                        let albumLevel = NowLocalEnrichment(
                            found: enrichment.found,
                            trackId: nil,
                            title: nil,
                            artist: enrichment.artist,
                            album: enrichment.album,
                            hasAnimatedArtwork: true,
                            animatedSquareUrl: enrichment.animatedSquareUrl,
                            animatedTallUrl: enrichment.animatedTallUrl,
                            isAtmos: enrichment.isAtmos,
                            isLossless: enrichment.isLossless,
                            lyricsUrl: nil,
                            lyricsType: nil
                        )
                        if cache[albKey] == nil || (cache[albKey]?.animatedTallUrl == nil && cache[albKey]?.animatedSquareUrl == nil) {
                            cache[albKey] = albumLevel
                        }
                        if cache[albOnlyKey] == nil || (cache[albOnlyKey]?.animatedTallUrl == nil && cache[albOnlyKey]?.animatedSquareUrl == nil) {
                            cache[albOnlyKey] = albumLevel
                        }
                    }
                }
            }
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

    private func titlesMatch(_ titleA: String, _ titleB: String) -> Bool {
        func normalize(_ s: String) -> String {
            var res = s.lowercased()
            res = res.replacingOccurrences(of: "^\\d+([\\.\\-\\s])+", with: "", options: .regularExpression)
            res = res.replacingOccurrences(of: "\\s*\\(.*?\\)", with: "", options: .regularExpression)
            res = res.replacingOccurrences(of: "\\s*\\[.*?\\]", with: "", options: .regularExpression)
            res = res.folding(options: .diacriticInsensitive, locale: .current)
            return res.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let normA = normalize(titleA)
        let normB = normalize(titleB)
        if normA.isEmpty || normB.isEmpty { return false }
        if normA == normB { return true }
        if normA.contains(normB) || normB.contains(normA) { return true }
        return false
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
                var effective = enrichment
                if let requestedTitle = title, !requestedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !titlesMatch(enrichment.title ?? "", requestedTitle) {
                        // The server matched the album and returned another track's lyrics!
                        // Strip lyrics so this song does not copy another song's lyrics
                        effective = NowLocalEnrichment(
                            found: enrichment.found,
                            trackId: nil,
                            title: nil,
                            artist: enrichment.artist,
                            album: enrichment.album,
                            hasAnimatedArtwork: enrichment.hasAnimatedArtwork,
                            animatedSquareUrl: enrichment.animatedSquareUrl,
                            animatedTallUrl: enrichment.animatedTallUrl,
                            isAtmos: enrichment.isAtmos,
                            isLossless: enrichment.isLossless,
                            lyricsUrl: nil,
                            lyricsType: nil
                        )
                    }
                }
                cache[cacheKey] = effective
                storeCachedEnrichment(effective, forKeys: [cacheKey, "\(album ?? "")_\(artist ?? "")_", "\(album ?? "")__"])
                return effective
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
            var exactTitleMatch = false
            for t in tracks {
                let tAlb = (t["album"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let tArt = (t["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let tTit = t["title"] as? String ?? ""

                if !titQ.isEmpty && titlesMatch(tTit, title ?? "") && (artQ.isEmpty || tArt.contains(artQ) || artQ.contains(tArt)) {
                    bestTrack = t
                    exactTitleMatch = true
                    break
                }
                if !albQ.isEmpty && tAlb == albQ && (artQ.isEmpty || tArt.contains(artQ) || artQ.contains(tArt)) {
                    if bestTrack == nil { bestTrack = t }
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

            let hasLyricsForThisTrack = (exactTitleMatch || titQ.isEmpty) && (track["lyrics_type"] as? String != "none")

            return NowLocalEnrichment(
                found: true,
                trackId: exactTitleMatch ? (track["id"] as? String) : nil,
                title: exactTitleMatch ? (track["title"] as? String) : nil,
                artist: track["artist"] as? String,
                album: track["album"] as? String,
                hasAnimatedArtwork: (track["has_animated_artwork"] as? Bool) ?? true,
                animatedSquareUrl: square,
                animatedTallUrl: tall,
                isAtmos: track["is_atmos"] as? Bool,
                isLossless: track["is_lossless"] as? Bool,
                lyricsUrl: hasLyricsForThisTrack ? "/api/lyrics/\(track["id"] ?? "")" : nil,
                lyricsType: hasLyricsForThisTrack ? (track["lyrics_type"] as? String) : nil
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
            if (title == nil || title?.isEmpty == true) || fastCached.title != nil {
                cache[cacheKey] = fastCached
                return fastCached
            }
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
                storeCachedEnrichment(libResult, forKeys: [cacheKey, "\(album ?? "")_\(artist ?? "")_", "\(album ?? "")__"])
                return libResult
            }
        }

        // For album enrichment, if artist-specific lookup failed, fallback to querying without artist
        if (title == nil || title?.isEmpty == true), let album, !album.isEmpty, artist != nil && !artist!.isEmpty {
            let albumOnlyKey = "\(album)__"
            if let cached = cache[albumOnlyKey] {
                return cached
            }
            for base in candidates {
                if let result = await performEnrichmentRequest(base: base, album: album, artist: nil, title: nil, cacheKey: albumOnlyKey) {
                    storeCachedEnrichment(result, forKeys: [albumOnlyKey, "\(album)_\(artist ?? "")_"])
                    return result
                }
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
