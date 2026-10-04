import SwiftUI
import SwiftData
import SwiftSonic

/// A value snapshot avoids SwiftData observation in each row. PersistentIdentifier
/// preserves row identity across query refreshes.
struct SearchHistoryRowData: Identifiable, Equatable {
    let id: PersistentIdentifier
    let coverArtId: String?
    let itemId: String
    let itemType: String
    let displayName: String
    let artistName: String?
    let albumName: String?

    init(entry: SearchHistoryEntry) {
        self.id = entry.persistentModelID
        self.coverArtId = entry.coverArtId
        self.itemId = entry.itemId
        self.itemType = entry.itemType
        self.displayName = entry.displayName
        self.artistName = entry.artistName
        self.albumName = entry.albumName
    }
}

/// Equatable skips row updates when a refreshed query yields unchanged values.
struct SearchHistoryEntryRow: View, Equatable {
    let data: SearchHistoryRowData
    var isDownloaded: Bool = false
    var onSelect: () -> Void = {}
    var onPlaySong: () -> Void = {}
    var onAddToPlaylist: ((DisplayableSong) -> Void)? = nil
    var onDownloadAlbum: (() -> Void)? = nil

    @Environment(\.appContainer) private var container

    static func == (lhs: SearchHistoryEntryRow, rhs: SearchHistoryEntryRow) -> Bool {
        lhs.data == rhs.data && lhs.isDownloaded == rhs.isDownloaded
    }

    private var isSong: Bool { data.itemType == "song" }
    private var isArtist: Bool { data.itemType == "artist" }
    private var isPlaylist: Bool { data.itemType == "playlist" }
    private var isAlbum: Bool { !isSong && !isArtist && !isPlaylist }

    private var isSingle: Bool {
        data.displayName.localizedCaseInsensitiveContains("single") || data.itemType == "single"
    }

    private var asDisplayableSong: DisplayableSong {
        DisplayableSong(
            id: data.itemId,
            title: data.displayName,
            artist: data.artistName,
            albumId: nil,
            albumName: data.albumName,
            artistId: nil,
            genre: nil,
            duration: 0,
            trackNumber: nil,
            isDownloaded: isDownloaded,
            coverArtId: data.coverArtId
        )
    }

    var body: some View {
        HStack(spacing: MinidiscSpacing.m) {
            Button {
                if isSong {
                    onPlaySong()
                } else {
                    onSelect()
                }
            } label: {
                HStack(spacing: MinidiscSpacing.m) {
                    artworkView
                    textContent
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            trailingAccessory
        }
        .padding(.vertical, 6)
        .padding(.horizontal, MinidiscSpacing.l)
        .contentShape(Rectangle())
        .contextMenu {
            if isSong {
                songContextMenu
            }
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        CoverArtView(id: data.coverArtId ?? data.itemId, size: 96)
            .frame(width: 48, height: 48)
            .clipShape(
                isArtist
                    ? AnyShape(Circle())
                    : AnyShape(RoundedRectangle(cornerRadius: MinidiscCornerRadius.standard))
            )
    }

    @ViewBuilder
    private var textContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(data.displayName)
                .font(.minidiscBody)
                .foregroundStyle(.primary)
                .lineLimit(1)

            if isArtist {
                Text("Artist")
                    .font(.minidiscCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if isPlaylist {
                Text("Playlist")
                    .font(.minidiscCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if isSong {
                let artistText = data.artistName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                Text(artistText.isEmpty ? "Song" : "Song • \(artistText)")
                    .font(.minidiscCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                let classification = isSingle ? "Single" : "Album"
                let artistText = data.artistName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                Text(artistText.isEmpty ? classification : "\(classification) • \(artistText)")
                    .font(.minidiscCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        if isSong {
            Menu {
                songContextMenu
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Options for \(data.displayName)")
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var songContextMenu: some View {
        let song = asDisplayableSong
        Button {
            onPlaySong()
        } label: {
            Label("Play", systemImage: "play.fill")
        }

        Button {
            Task {
                await container?.playerService.playNext(song)
                container?.toastService.show(String(localized: "Playing Next"), subtitle: song.title, style: .success)
            }
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }

        Button {
            Task {
                await container?.playerService.addToQueue(song)
                container?.toastService.show(String(localized: "Playing Last"), subtitle: song.title, style: .success)
            }
        } label: {
            Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
        }

        if let onAddToPlaylist {
            Button {
                onAddToPlaylist(song)
            } label: {
                Label("Add to a Playlist…", systemImage: "text.badge.plus")
            }
        }

        ShareLink(item: "\(song.title) - \(song.artist ?? "")") {
            Label("Share Song…", systemImage: "square.and.arrow.up")
        }
    }
}
