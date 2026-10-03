import Foundation
import CryptoKit
import OSLog

actor MotionArtworkCache {
    static let shared = MotionArtworkCache()

    private let cacheDirectory: URL
    private var inFlightDownloads: [URL: Task<URL, Error>] = [:]

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = caches.appendingPathComponent("app.minidisc/motion_artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private static func cacheKey(for remoteURL: URL) -> String {
        if let components = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false) {
            let artType = remoteURL.path.contains("square") ? "square" : (remoteURL.path.contains("tall") ? "tall" : "video")
            if let v = components.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
                return "artwork_\(artType)_\(v)"
            }
        }
        return remoteURL.absoluteString
    }

    private func localFileURL(for remoteURL: URL) -> URL {
        let key = Self.cacheKey(for: remoteURL)
        let hash = SHA256.hash(data: Data(key.utf8))
        let filename = hash.compactMap { String(format: "%02x", $0) }.joined() + ".mp4"
        return cacheDirectory.appendingPathComponent(filename)
    }

    nonisolated func cachedURL(for remoteURL: URL) -> URL? {
        let key = Self.cacheKey(for: remoteURL)
        let hash = SHA256.hash(data: Data(key.utf8))
        let filename = hash.compactMap { String(format: "%02x", $0) }.joined() + ".mp4"
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let file = caches.appendingPathComponent("app.minidisc/motion_artwork", isDirectory: true).appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: file.path) {
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
            if size > 1024 {
                return file
            }
        }
        return nil
    }

    func loadOrDownload(for remoteURL: URL) async throws -> URL {
        if let local = cachedURL(for: remoteURL) {
            return local
        }
        if let existing = inFlightDownloads[remoteURL] {
            return try await existing.value
        }
        let task = Task<URL, Error> {
            let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let dest = self.localFileURL(for: remoteURL)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)
            return dest
        }
        inFlightDownloads[remoteURL] = task
        defer { inFlightDownloads.removeValue(forKey: remoteURL) }
        return try await task.value
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}
