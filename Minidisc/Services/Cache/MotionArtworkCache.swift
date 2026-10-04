import Foundation
import CryptoKit
import OSLog
import AVFoundation

private nonisolated final class FirstFrameMemoryCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: PlatformImage] = [:]

    nonisolated func get(_ key: String) -> PlatformImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }

    nonisolated func set(_ image: PlatformImage, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        cache[key] = image
    }

    nonisolated func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}

actor MotionArtworkCache {
    static let shared = MotionArtworkCache()

    private let cacheDirectory: URL
    private var inFlightDownloads: [URL: Task<URL, Error>] = [:]
    nonisolated private static let firstFrames = FirstFrameMemoryCache()

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

    nonisolated func firstFrame(for remoteURL: URL) -> PlatformImage? {
        let key = Self.cacheKey(for: remoteURL)
        if let memory = Self.firstFrames.get(key) {
            return memory
        }

        guard let local = cachedURL(for: remoteURL) else { return nil }

        let asset = AVURLAsset(url: local)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 800)
        if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            let img = PlatformImage(cgImage: cgImage)
            Self.firstFrames.set(img, for: key)
            return img
        }
        return nil
    }

    func loadOrDownload(for remoteURL: URL) async throws -> URL {
        if let local = cachedURL(for: remoteURL) {
            _ = firstFrame(for: remoteURL)
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
            _ = self.firstFrame(for: remoteURL)
            return dest
        }
        inFlightDownloads[remoteURL] = task
        defer { inFlightDownloads.removeValue(forKey: remoteURL) }
        return try await task.value
    }

    func clearCache() {
        Self.firstFrames.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}
