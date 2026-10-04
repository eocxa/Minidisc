import Foundation
import SwiftSonic

nonisolated struct DisplayableSong: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let title: String
    let artist: String?
    let albumId: String?
    let albumName: String?
    let artistId: String?
    let genre: String?
    let duration: TimeInterval
    var discNumber: Int? = nil
    let trackNumber: Int?
    var isDownloaded: Bool
    let coverArtId: String?
    let audioFormat: String?
    let replayGainTrackGain: Double?
    let replayGainTrackPeak: Double?
    let replayGainAlbumGain: Double?
    let replayGainAlbumPeak: Double?
    /// OpenSubsonic: always added to the selected mode's gain when present.
    let replayGainBaseGain: Double?
    /// OpenSubsonic: used as fallback when the selected mode's gain is absent.
    let replayGainFallbackGain: Double?
    var localFile: LocalFileReference? = nil

    var isLocalFile: Bool { localFile != nil }

    nonisolated init(
        id: String,
        title: String,
        artist: String? = nil,
        albumId: String? = nil,
        albumName: String? = nil,
        artistId: String? = nil,
        genre: String? = nil,
        duration: TimeInterval = 0,
        discNumber: Int? = nil,
        trackNumber: Int? = nil,
        isDownloaded: Bool = false,
        coverArtId: String? = nil,
        audioFormat: String? = nil,
        replayGainTrackGain: Double? = nil,
        replayGainTrackPeak: Double? = nil,
        replayGainAlbumGain: Double? = nil,
        replayGainAlbumPeak: Double? = nil,
        replayGainBaseGain: Double? = nil,
        replayGainFallbackGain: Double? = nil,
        localFile: LocalFileReference? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.albumId = albumId
        self.albumName = albumName
        self.artistId = artistId
        self.genre = genre
        self.duration = duration
        self.discNumber = discNumber
        self.trackNumber = trackNumber
        self.isDownloaded = isDownloaded
        self.coverArtId = coverArtId
        self.audioFormat = audioFormat
        self.replayGainTrackGain = replayGainTrackGain
        self.replayGainTrackPeak = replayGainTrackPeak
        self.replayGainAlbumGain = replayGainAlbumGain
        self.replayGainAlbumPeak = replayGainAlbumPeak
        self.replayGainBaseGain = replayGainBaseGain
        self.replayGainFallbackGain = replayGainFallbackGain
        self.localFile = localFile
    }
}

extension DisplayableSong {
    nonisolated init(from song: Song, isDownloaded: Bool = false) {
        self.id = song.id
        self.title = song.title
        self.artist = song.artist
        self.albumId = song.albumId
        self.albumName = song.album
        self.artistId = song.artistId
        self.genre = song.genres?.first?.name ?? song.genre
        self.duration = song.duration.map(TimeInterval.init) ?? 0
        self.discNumber = song.discNumber
        self.trackNumber = song.track
        self.isDownloaded = isDownloaded
        self.coverArtId = song.coverArt
        self.audioFormat = song.suffix?.uppercased()
        self.replayGainTrackGain = song.replayGain?.trackGain
        self.replayGainTrackPeak = song.replayGain?.trackPeak
        self.replayGainAlbumGain = song.replayGain?.albumGain
        self.replayGainAlbumPeak = song.replayGain?.albumPeak
        self.replayGainBaseGain = song.replayGain?.baseGain
        self.replayGainFallbackGain = song.replayGain?.fallbackGain
    }

    @MainActor
    init(from track: DownloadedTrack) {
        self.id = track.songId
        self.title = track.title
        self.artist = track.artist
        self.albumId = track.albumId
        self.albumName = track.album
        self.artistId = track.artistId
        self.genre = track.genre
        self.duration = track.durationSeconds.map(TimeInterval.init) ?? 0
        self.discNumber = track.discNumber
        self.trackNumber = track.trackNumber
        self.isDownloaded = true
        self.coverArtId = track.coverArtId
        self.audioFormat = track.suffix?.uppercased()
        self.replayGainTrackGain = track.replayGainTrackGain
        self.replayGainTrackPeak = track.replayGainTrackPeak
        self.replayGainAlbumGain = track.replayGainAlbumGain
        self.replayGainAlbumPeak = track.replayGainAlbumPeak
        self.replayGainBaseGain = track.replayGainBaseGain
        self.replayGainFallbackGain = track.replayGainFallbackGain
    }

    func withDownloaded(_ flag: Bool) -> DisplayableSong {
        var copy = self
        copy.isDownloaded = flag
        return copy
    }
}
