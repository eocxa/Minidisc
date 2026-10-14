import Foundation

// MARK: - Player navigation helpers

func postNavigateToAlbum(track: DisplayableSong) {
    guard let albumId = track.albumId else { return }
    NotificationCenter.default.post(
        name: .minidiscNavigateToAlbum,
        object: nil,
        userInfo: [
            "albumId":   albumId,
            "albumName": track.albumName ?? "",
            "coverArtId": track.coverArtId as Any
        ]
    )
}

@MainActor
func navigateToAlbum(track: DisplayableSong, container: AppContainer?) {
    if track.albumId != nil {
        postNavigateToAlbum(track: track)
        return
    }
    guard let name = track.albumName, !name.isEmpty else { return }
    Task {
        guard let c = container,
              let result = try? await c.libraryService.search(name),
              let found = result.album?.first else { return }
        NotificationCenter.default.post(
            name: .minidiscNavigateToAlbum,
            object: nil,
            userInfo: [
                "albumId":   found.id,
                "albumName": found.name,
                "coverArtId": found.coverArt as Any
            ]
        )
    }
}

@MainActor
func navigateToArtist(track: DisplayableSong, container: AppContainer?) {
    if track.artistId != nil {
        postNavigateToArtist(track: track)
        return
    }
    guard let name = track.artist, !name.isEmpty else { return }
    Task {
        guard let c = container,
              let result = try? await c.libraryService.search(name),
              let found = result.artist?.first else { return }
        postNavigateToArtist(artistId: found.id, artistName: found.name, coverArtId: found.coverArt)
    }
}

func postNavigateToArtist(track: DisplayableSong) {
    guard let artistId = track.artistId else { return }
    postNavigateToArtist(artistId: artistId, artistName: track.artist ?? "", coverArtId: track.coverArtId)
}

func postNavigateToArtist(artistId: String, artistName: String, coverArtId: String?) {
    NotificationCenter.default.post(
        name: .minidiscNavigateToArtist,
        object: nil,
        userInfo: [
            "artistId":   artistId,
            "artistName": artistName,
            "coverArtId": coverArtId as Any
        ]
    )
}

func postNavigateToPlaylist(playlistId: String, name: String, coverArtId: String?) {
    NotificationCenter.default.post(
        name: .minidiscNavigateToPlaylist,
        object: nil,
        userInfo: [
            "playlistId": playlistId,
            "name":       name,
            "coverArtId": coverArtId as Any
        ]
    )
}

/// A playlist was deleted (server-confirmed) from a detail surface. The playlist list observes this to reload,
/// so the deleted playlist disappears on return without a manual refresh — and without an `.onAppear` reload.
func postPlaylistDeleted() {
    NotificationCenter.default.post(name: .minidiscPlaylistDeleted, object: nil)
}

extension Notification.Name {
    static let minidiscNavigateToLibrary = Notification.Name("minidiscNavigateToLibrary")
    static let minidiscNavigateToDownloads = Notification.Name("minidiscNavigateToDownloads")
    static let minidiscNavigateToAlbum    = Notification.Name("minidiscNavigateToAlbum")
    static let minidiscNavigateToArtist   = Notification.Name("minidiscNavigateToArtist")
    static let minidiscNavigateToPlaylist = Notification.Name("minidiscNavigateToPlaylist")
    static let minidiscPlaylistDeleted    = Notification.Name("minidisc.playlistDeleted")
    static let minidiscOfflineLibraryChanged = Notification.Name("minidisc.offlineLibraryChanged")
    static let minidiscFavoritesChanged = Notification.Name("minidisc.favoritesChanged")
    static let minidiscPlaylistsChanged   = Notification.Name("minidisc.playlistsChanged")
    static let minidiscMoodPlaylistsChanged = Notification.Name("minidisc.moodPlaylistsChanged")
    static let lidarrLibraryDidChange     = Notification.Name("minidisc.lidarrLibraryDidChange")
    static let lidarrQueueDidChange       = Notification.Name("minidisc.lidarrQueueDidChange")
}

func postOfflineLibraryChanged() {
    NotificationCenter.default.post(name: .minidiscOfflineLibraryChanged, object: nil)
}
