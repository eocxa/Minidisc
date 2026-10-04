import Foundation
import CryptoKit
import OSLog
import AVFoundation
import UIKit

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

private nonisolated final class PersistFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool = true

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Bool) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}

actor MotionArtworkCache {
    static let shared = MotionArtworkCache()

    private let cacheDirectory: URL
    private var inFlightDownloads: [URL: Task<URL, Error>] = [:]
    nonisolated private static let firstFrames = FirstFrameMemoryCache()
    private static let persistFlag = PersistFlag()

    nonisolated var persistMotionArtworkEnabled: Bool {
        get { Self.persistFlag.get() }
        set { Self.persistFlag.set(newValue) }
    }

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = caches.appendingPathComponent("app.minidisc/motion_artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private static func cacheKey(for remoteURL: URL) -> String {
        let path = remoteURL.path
        if let components = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false) {
            let v = components.queryItems?.first(where: { $0.name == "v" })?.value ?? ""
            return "\(path)_\(v)"
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
        guard persistMotionArtworkEnabled else { return nil }
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

    func extractFirstFrame(for remoteURL: URL) async -> PlatformImage? {
        let key = Self.cacheKey(for: remoteURL)
        if let memory = Self.firstFrames.get(key) {
            return memory
        }

        guard let local = cachedURL(for: remoteURL) else { return nil }

        let asset = AVURLAsset(url: local)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 800)
        if let (cgImage, _) = try? await generator.image(at: .zero) {
            let img = PlatformImage(cgImage: cgImage)
            Self.firstFrames.set(img, for: key)
            return img
        }
        return nil
    }

    nonisolated func firstFrame(for remoteURL: URL) -> PlatformImage? {
        let key = Self.cacheKey(for: remoteURL)
        if let memory = Self.firstFrames.get(key) {
            return memory
        }

        guard cachedURL(for: remoteURL) != nil else { return nil }

        Task {
            _ = await self.extractFirstFrame(for: remoteURL)
        }
        return nil
    }

    func loadOrDownload(for remoteURL: URL) async throws -> URL {
        if !persistMotionArtworkEnabled {
            _ = await extractFirstFrame(for: remoteURL)
            return remoteURL
        }
        if let local = cachedURL(for: remoteURL) {
            _ = await extractFirstFrame(for: remoteURL)
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
            _ = await self.extractFirstFrame(for: remoteURL)
            return dest
        }
        inFlightDownloads[remoteURL] = task
        defer { inFlightDownloads.removeValue(forKey: remoteURL) }
        return try await task.value
    }

    nonisolated func motionArtworkStats() -> (count: Int, bytes: Int64) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("app.minidisc/motion_artwork", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return (0, 0) }
        var bytes: Int64 = 0
        var count = 0
        for file in files {
            let ext = file.pathExtension.lowercased()
            if ext == "mp4" || ext == "m4v" || ext == "mov" {
                count += 1
                bytes += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
        }
        return (count, bytes)
    }

    func clearCache() {
        Self.firstFrames.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}
