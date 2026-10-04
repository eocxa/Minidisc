import SwiftUI
import SwiftSonic
import SwiftData
import OSLog

// MARK: - Mode

enum AlbumDetailMode: Sendable {
    case full           // show all album songs (default — online catalog browsing)
    case downloadedOnly // show only downloaded tracks (Downloads/Offline contexts for purely-partial albums)
}

private struct AlbumRecommendationRequest: Equatable {
    let albumId: String
    let artistId: String?
    let artistName: String?
}

struct AlbumDetailView: View {
    private let albumId: String
    private let initialName: String
    private let initialArtistId: String?
    private let initialArtistName: String?
    private let coverArtId: String?
    private let initialCoverImage: PlatformImage?
    private let zoomSourceId: String?
    private let zoomNamespace: Namespace.ID?
    private let mode: AlbumDetailMode

    init(album: AlbumID3, zoomSourceId: String? = nil, zoomNamespace: Namespace.ID? = nil, coverArtId: String? = nil, initialDominantColor: Color = .clear, initialCoverImage: PlatformImage? = nil, mode: AlbumDetailMode = .full) {
        albumId = album.id
        initialName = album.name
        initialArtistId = album.artistId
        initialArtistName = album.artist
        self.coverArtId = coverArtId
        self.initialCoverImage = initialCoverImage
        let cid = "album:\(album.id)"
        let aid = album.id
        _albumFavoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == cid })
        _downloadedAlbumTracks = Query(filter: #Predicate<DownloadedTrack> { $0.albumId == aid })
        self.zoomSourceId = zoomSourceId
        self.zoomNamespace = zoomNamespace
        self.mode = mode
        _dominantColor = State(initialValue: initialDominantColor)
        let initialEnrichment = NowLocalService.shared.cachedEnrichment(album: album.name, artist: album.artist)
            ?? NowLocalService.shared.cachedEnrichment(album: album.name, artist: nil)
        let albClean = album.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let initialEnrichment,
           let enAlb = initialEnrichment.album?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !enAlb.isEmpty && !albClean.isEmpty && enAlb == albClean {
            _enrichment = State(initialValue: initialEnrichment)
            let hasCachedVideo = initialEnrichment.animatedTallUrl != nil || initialEnrichment.animatedSquareUrl != nil
            _isMotionVideoReady = State(initialValue: hasCachedVideo)
        } else {
            _enrichment = State(initialValue: nil)
            _isMotionVideoReady = State(initialValue: false)
        }
    }

    init(albumId: String, albumName: String, zoomSourceId: String? = nil, zoomNamespace: Namespace.ID? = nil, coverArtId: String? = nil, initialDominantColor: Color = .clear, initialCoverImage: PlatformImage? = nil, mode: AlbumDetailMode = .full) {
        self.albumId = albumId
        self.initialName = albumName
        initialArtistId = nil
        initialArtistName = nil
        self.coverArtId = coverArtId
        self.initialCoverImage = initialCoverImage
        let cid = "album:\(albumId)"
        let aid = albumId
        _albumFavoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == cid })
        _downloadedAlbumTracks = Query(filter: #Predicate<DownloadedTrack> { $0.albumId == aid })
        self.zoomSourceId = zoomSourceId
        self.zoomNamespace = zoomNamespace
        self.mode = mode
        _dominantColor = State(initialValue: initialDominantColor)
        let initialEnrichment = NowLocalService.shared.cachedEnrichment(album: albumName, artist: nil)
        let albClean = albumName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let initialEnrichment,
           let enAlb = initialEnrichment.album?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !enAlb.isEmpty && !albClean.isEmpty && enAlb == albClean {
            _enrichment = State(initialValue: initialEnrichment)
            let hasCachedVideo = initialEnrichment.animatedTallUrl != nil || initialEnrichment.animatedSquareUrl != nil
            _isMotionVideoReady = State(initialValue: hasCachedVideo)
        } else {
            _enrichment = State(initialValue: nil)
            _isMotionVideoReady = State(initialValue: false)
        }
    }

    @Environment(\.appContainer) private var container
    @Environment(PlaylistAddition.self) private var playlistAddition
    @State private var songSelection: SongSelectionRequest?
    @Environment(\.dismiss) private var dismiss
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: AlbumDetailViewModel?
    @State private var dominantColor: Color = .clear
    @State private var showDeleteAlert = false
    @State private var showThemeColorSheet = false
    @State private var recommendedAlbums: [AlbumID3] = []
    @State private var enrichment: NowLocalEnrichment?
    @State private var isMotionVideoReady = false
    @Query private var albumFavoriteMatches: [FavoriteRecord]
    @Query private var downloadedAlbumTracks: [DownloadedTrack]

    private var effectiveEnrichment: NowLocalEnrichment? {
        let album = (viewModel?.albumName ?? initialName).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let enrichment {
            if let enAlb = enrichment.album?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !enAlb.isEmpty && !album.isEmpty && enAlb != album {
                // Ignore mismatched enrichment
            } else {
                return enrichment
            }
        }
        let rawAlbum = viewModel?.albumName ?? initialName
        let rawArtist = viewModel?.artistName ?? initialArtistName
        let cached = NowLocalService.shared.cachedEnrichment(album: rawAlbum, artist: rawArtist)
            ?? NowLocalService.shared.cachedEnrichment(album: rawAlbum, artist: nil)
        if let cached,
           let enAlb = cached.album?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !enAlb.isEmpty && !album.isEmpty && enAlb != album {
            return nil
        }
        return cached
    }

    private var resolvedAnimatedSquareURL: URL? {
        guard !UserDefaults.standard.bool(forKey: "minidisc_motion_artwork_disabled") else { return nil }
        return NowLocalService.shared.resolveArtworkURL(
            path: effectiveEnrichment?.animatedSquareUrl,
            activeServerBaseURL: container?.serverState.activeServer?.baseURL
        )
    }

    private var resolvedAnimatedTallURL: URL? {
        guard !UserDefaults.standard.bool(forKey: "minidisc_motion_artwork_disabled") else { return nil }
        return NowLocalService.shared.resolveArtworkURL(
            path: effectiveEnrichment?.animatedTallUrl,
            activeServerBaseURL: container?.serverState.activeServer?.baseURL
        )
    }

    private var resolvedAnimatedCoverURL: URL? {
        resolvedAnimatedTallURL ?? resolvedAnimatedSquareURL
    }

    private var hasTallAnimatedCover: Bool {
        resolvedAnimatedTallURL != nil
    }

    private var hasAnimatedCover: Bool {
        resolvedAnimatedCoverURL != nil
    }

    private var isAlbumFavorite: Bool { !albumFavoriteMatches.isEmpty }
    private var isOnline: Bool { container?.serverState.isOnline == true }
    private var albumCoverId: String { viewModel?.coverArtId ?? coverArtId ?? albumId }
    /// Every cover id the override must cover so it's resolved from ANY surface: the album cover + each song's
    /// own cover id (these can differ from the album's while pointing at the same artwork — e.g. the full player).
    private var albumThemeIds: [String] {
        [albumCoverId] + (viewModel?.songs.compactMap { $0.coverArtId } ?? [])
    }
    private func resetThemeColor() {
        colorExtractor.setColorOverride(nil, forIds: albumThemeIds)
        dominantColor = colorExtractor.cachedColor(for: albumCoverId) ?? dominantColor
    }
    private var isLoadingSkeleton: Bool {
        viewModel == nil || (viewModel?.isLoading == true && viewModel?.songs.isEmpty == true)
    }
    private var palette: AlbumDetailPalette {
        AlbumDetailPalette(dominantColor: dominantColor, appearance: colorScheme)
    }
    private var headerTextColor: Color { palette.contentColor }
    private var headerSecondaryColor: Color { palette.secondaryContentColor }

    private var recommendationRequest: AlbumRecommendationRequest? {
        guard case .full = mode,
              isOnline else {
            return nil
        }

        return AlbumRecommendationRequest(
            albumId: albumId,
            artistId: initialArtistId,
            artistName: initialArtistName
        )
    }

    private var visibleRecommendedAlbums: [AlbumID3] {
        let excludedArtistId = viewModel?.artistId ?? initialArtistId
        let excludedArtistName = (viewModel?.artistName ?? initialArtistName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return Array(
            recommendedAlbums.lazy
                .filter { album in
                    if let excludedArtistId, album.artistId == excludedArtistId {
                        return false
                    }
                    if let excludedArtistName,
                       album.artist?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                           == excludedArtistName {
                        return false
                    }
                    return true
                }
                .prefix(AlbumYouMightAlsoLikeSection.resultLimit)
        )
    }

    private var effectiveInitialImage: PlatformImage? {
        initialCoverImage ?? artworkImageCache.cachedImage(for: coverArtId ?? albumId)
    }

    // MARK: - Song filtering

    private var offlineFallbackSongs: [DisplayableSong] {
        downloadedAlbumTracks
            .sorted { ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max) }
            .map { DisplayableSong(from: $0) }
    }

    private func filteredSongs(_ vmSongs: [DisplayableSong]) -> [DisplayableSong] {
        switch mode {
        case .full:
            return vmSongs
        case .downloadedOnly:
            let downloadedIds = Set(downloadedAlbumTracks.map(\.songId))
            return vmSongs.filter { downloadedIds.contains($0.id) }
        }
    }

    private func displaySongs() -> [DisplayableSong] {
        if !isOnline {
            let local = container?.offlineLibrary.snapshot.albumSongs(albumId) ?? []
            return mode == .downloadedOnly ? local.filter(\.isDownloaded) : local
        }
        switch mode {
        case .downloadedOnly:
            if let vm = viewModel, vm.error == nil, !vm.songs.isEmpty {
                return filteredSongs(vm.songs)
            }
            return offlineFallbackSongs
        case .full:
            // Fall back to downloaded tracks if the catalogue fails or returns an empty response.
            if let vm = viewModel, !vm.songs.isEmpty {
                return vm.songs
            }
            return offlineFallbackSongs
        }
    }

    private func shouldShowTrackArtists(in songs: [DisplayableSong]) -> Bool {
        let trackArtists = Set(
            songs.compactMap { song -> String? in
                guard let artist = song.artist?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !artist.isEmpty else { return nil }
                return artist.lowercased()
            }
        )

        if trackArtists.count > 1 {
            return true
        }

        guard let trackArtist = trackArtists.first,
              let albumArtist = viewModel?.artistName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
              !albumArtist.isEmpty else {
            return false
        }

        return trackArtist != albumArtist
    }

    private var topScrollEdges: Edge.Set {
        hasTallAnimatedCover ? .top : []
    }

    private var enrichmentKey: String {
        "\(viewModel?.albumName ?? initialName)_\(viewModel?.artistName ?? initialArtistName ?? "")"
    }

    @ViewBuilder
    private var scrollContent: some View {
        let hasAnimated = hasAnimatedCover
        let songs = displaySongs()

        ScrollView {
            LazyVStack(spacing: 0) {
                headerSection(hasAnimatedCover: hasAnimated)

                AlbumPlaybackActions(
                    albumId: albumId,
                    songs: songs,
                    mode: mode,
                    viewModel: viewModel,
                    downloadedAlbumTracks: downloadedAlbumTracks,
                    contentColor: palette.contentColor,
                    controlFillColor: palette.controlFillColor,
                    playLabelColor: palette.playLabelColor,
                    showDeleteAlert: $showDeleteAlert
                )
                .padding(.top, MinidiscSpacing.l)
                .padding(.bottom, MinidiscSpacing.xl)

                if isLoadingSkeleton {
                    AlbumTrackSkeletonRows()
                } else if let vm = viewModel {
                    trackListContent(songs: songs, vm: vm)
                }
            }
        }
        .contentMargins(.top, hasTallAnimatedCover ? 0 : 0, for: .scrollContent)
        .ignoresSafeArea(.all, edges: topScrollEdges)
        .toolbarBackground(.hidden, for: .navigationBar)
        .refreshable { await viewModel?.load() }
        .miniPlayerBottomMargin()
        .animation(.easeInOut(duration: 0.35), value: isMotionVideoReady)
        .minidiscHideTopScrollEdgeEffect()
        .minidiscSongSwipeContainer()
    }

    @ToolbarContentBuilder
    private var albumToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("Back", systemImage: "chevron.left") {
                dismiss()
            }
            .tint(palette.contentColor)
        }
        ToolbarItem(placement: .primaryAction) {
            favoriteToolbarButton
        }
        ToolbarItem(placement: .primaryAction) {
            albumOptionsMenu
        }
    }

    @ViewBuilder
    private var favoriteToolbarButton: some View {
        Button(
            isAlbumFavorite ? "Remove from Favorites" : "Add to Favorites",
            systemImage: isAlbumFavorite ? "star.fill" : "star"
        ) {
            HapticFeedback.light.trigger()
            Task {
                if isAlbumFavorite {
                    await container?.toastService.perform { try await container?.favoritesService.unstar(itemType: .album, itemId: albumId) }
                } else {
                    await container?.toastService.perform { try await container?.favoritesService.star(itemType: .album, itemId: albumId) }
                }
            }
        }
        .tint(palette.contentColor)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isAlbumFavorite)
        .disabled(!isOnline)
    }

    @ViewBuilder
    private var albumOptionsMenu: some View {
        Menu("More options", systemImage: "ellipsis") {
            Group {
                Button("Select Songs", systemImage: "checkmark.circle") {
                    songSelection = SongSelectionRequest(songs: displaySongs())
                }
                .disabled(container?.serverState.isOnline != true || displaySongs().isEmpty)
                Divider()
                Button("Instant Mix", systemImage: instantMixSymbol) {
                    HapticFeedback.medium.trigger()
                    startInstantMix(from: .album(id: albumId), using: container)
                }
                .disabled(displaySongs().isEmpty || !isOnline)
                Divider()
                Button("Theme colour", systemImage: "paintpalette") {
                    showThemeColorSheet = true
                }
                if colorExtractor.colorOverride(for: albumCoverId) != nil {
                    Button("Reset to cover colour", systemImage: "arrow.uturn.backward") {
                        resetThemeColor()
                    }
                }
            }
            .tint(palette.contentColor)
        }
        .tint(palette.contentColor)
    }

    @ViewBuilder
    private var themeColorSheetView: some View {
        ThemeColorSheet(
            color: Binding(
                get: { colorExtractor.cachedColor(for: albumCoverId) ?? dominantColor },
                set: { newColor in
                    colorExtractor.setColorOverride(newColor, forIds: albumThemeIds)
                    dominantColor = newColor
                }
            ),
            hasOverride: colorExtractor.colorOverride(for: albumCoverId) != nil,
            footerText: "Overrides the colour taken from the cover, here and anywhere else this album appears.",
            onReset: resetThemeColor
        )
    }

    private func handleServerOnlineChanged() async {
        guard let c = container else { return }
        if viewModel == nil {
            viewModel = AlbumDetailViewModel(
                albumId: albumId,
                libraryService: c.libraryService,
                downloadService: c.downloadService,
                toastService: c.toastService,
                serverState: c.serverState,
                offlineFavorites: mode == .downloadedOnly ? nil : c.offlineFavoritesStore
            )
        }
        await viewModel?.load()
    }

    private func handleCoverArtChanged(artId: String?) async {
        guard let artId else { return }
        let cached = colorExtractor.dominantColor(for: artId, image: nil)
        if cached != .clear {
            dominantColor = cached
            return
        }
        await loadDominantColor(coverArtId: artId)
    }

    private func handleRecommendationChanged(request: AlbumRecommendationRequest?) async {
        guard let request else {
            recommendedAlbums = []
            return
        }
        await loadAlbumRecommendations(for: request)
    }

    private func handleEnrichmentTask() async {
        let album = viewModel?.albumName ?? initialName
        let artist = viewModel?.artistName ?? initialArtistName
        let currentCleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // If existing enrichment is for another album, clear it immediately
        if let existing = enrichment,
           let enAlb = existing.album?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !enAlb.isEmpty && !currentCleanAlbum.isEmpty && enAlb != currentCleanAlbum {
            enrichment = nil
            isMotionVideoReady = false
        }

        if enrichment == nil {
            if let cached = NowLocalService.shared.cachedEnrichment(album: album, artist: artist)
                ?? NowLocalService.shared.cachedEnrichment(album: album, artist: nil) {
                let enAlb = cached.album?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                if !enAlb.isEmpty && !currentCleanAlbum.isEmpty && enAlb == currentCleanAlbum {
                    enrichment = cached
                    let hasCachedVideo = cached.animatedTallUrl != nil || cached.animatedSquareUrl != nil
                    isMotionVideoReady = hasCachedVideo
                }
            }
        }

        var fetched = await NowLocalService.shared.fetchEnrichment(
            album: album,
            artist: artist,
            activeServerBaseURL: container?.serverState.activeServer?.baseURL
        )
        // Verify fetched album strictly matches!
        if let f = fetched,
           let fAlb = f.album?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           fAlb != currentCleanAlbum {
            fetched = nil
        }

        if (fetched?.animatedTallUrl == nil && fetched?.animatedSquareUrl == nil) && !album.isEmpty {
            let fallback = await NowLocalService.shared.fetchEnrichment(
                album: album,
                artist: nil,
                activeServerBaseURL: container?.serverState.activeServer?.baseURL
            )
            if let fallback, fallback.animatedTallUrl != nil || fallback.animatedSquareUrl != nil {
                let fbAlb = fallback.album?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                if !fbAlb.isEmpty && !currentCleanAlbum.isEmpty && fbAlb == currentCleanAlbum {
                    fetched = NowLocalEnrichment(
                        found: true,
                        trackId: fetched?.trackId ?? fallback.trackId,
                        title: fetched?.title ?? fallback.title,
                        artist: fetched?.artist ?? fallback.artist ?? artist,
                        album: fetched?.album ?? fallback.album ?? album,
                        hasAnimatedArtwork: true,
                        animatedSquareUrl: fallback.animatedSquareUrl ?? fetched?.animatedSquareUrl,
                        animatedTallUrl: fallback.animatedTallUrl ?? fetched?.animatedTallUrl,
                        isAtmos: fetched?.isAtmos ?? fallback.isAtmos,
                        isLossless: fetched?.isLossless ?? fallback.isLossless,
                        lyricsUrl: fetched?.lyricsUrl ?? fallback.lyricsUrl,
                        lyricsType: fetched?.lyricsType ?? fallback.lyricsType
                    )
                }
            }
        }
        if let effective = fetched {
            withAnimation(.easeInOut(duration: 0.35)) {
                enrichment = effective
                isMotionVideoReady = effective.animatedTallUrl != nil || effective.animatedSquareUrl != nil
            }
            NowLocalService.shared.storeCachedEnrichment(
                effective,
                forKeys: [
                    "\(album)_\(artist ?? "")_",
                    "\(album)__"
                ]
            )
        } else {
            withAnimation(.easeInOut(duration: 0.35)) {
                enrichment = nil
                isMotionVideoReady = false
            }
        }
    }

    var body: some View {
        scrollContent
            .ignoresSafeArea(.container, edges: topScrollEdges)
            .alert("Remove downloaded album?", isPresented: $showDeleteAlert) {
                Button("Remove", role: .destructive) { Task { await viewModel?.deleteDownload() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The audio files will be deleted from this device.")
            }
            .background(AlbumDetailPageBackground(palette: palette))
            .minidiscContentWidth()
            .environment(\.minidiscPlayingAccent, palette.contentColor)
            .environment(\.colorScheme, palette.preferredContentScheme ?? colorScheme)
            .navigationTitle("")
            .navigationBarTitleDisplayModeInline()
            .navigationBarBackButtonHidden(true)
            .enableSwipeBack()
            .toolbar { albumToolbarContent }
            .sheet(item: $songSelection) { SongSelectionSheet(request: $0) }
            .sheet(isPresented: $showThemeColorSheet) { themeColorSheetView }
            .toolbarColorScheme(palette.preferredContentScheme, for: .navigationBar)
            .task(id: container?.serverState.isOnline) {
                await handleServerOnlineChanged()
            }
            .task(id: viewModel?.coverArtId) {
                await handleCoverArtChanged(artId: viewModel?.coverArtId)
            }
            .task(id: recommendationRequest) {
                await handleRecommendationChanged(request: recommendationRequest)
            }
            .task(id: enrichmentKey) {
                await handleEnrichmentTask()
            }
            .minidiscZoomTransition(sourceID: zoomSourceId, in: zoomNamespace)
    }

    // MARK: - Color loading

    private func loadDominantColor(coverArtId: String) async {
        guard let image = await container?.artworkImageCache.load(coverArtId: coverArtId) else { return }
        let color = colorExtractor.dominantColor(for: coverArtId, image: image)
        withAnimation(.easeIn(duration: 0.2)) {
            dominantColor = color
        }
    }

    private func loadAlbumRecommendations(for request: AlbumRecommendationRequest) async {
        guard let container else {
            recommendedAlbums = []
            return
        }

        do {
            let needsArtistFilteringAfterAlbumLoad = request.artistId == nil
                && request.artistName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            let requestLimit = AlbumYouMightAlsoLikeSection.resultLimit
                + (needsArtistFilteringAfterAlbumLoad ? 2 : 0)
            let recommendations = try await container.libraryService.similarAlbums(
                to: request.albumId,
                excludingArtistID: request.artistId,
                excludingArtistName: request.artistName,
                limit: requestLimit
            )
            try Task.checkCancellation()
            recommendedAlbums = recommendations
        } catch is CancellationError {
            return
        } catch {
            recommendedAlbums = []
            Logger.library.warning(
                "Unable to load album recommendations for \(request.albumId, privacy: .public): \(error, privacy: .public)"
            )
        }
    }

    // MARK: - Subviews for type-check performance

    @ViewBuilder
    private func headerSection(hasAnimatedCover: Bool) -> some View {
        AlbumArtworkSection(
            coverArtId: viewModel?.coverArtId ?? coverArtId ?? albumId,
            coverImage: effectiveInitialImage,
            albumName: viewModel?.albumName ?? initialName,
            animatedURL: resolvedAnimatedCoverURL,
            isTall: hasTallAnimatedCover,
            isVideoReady: isMotionVideoReady,
            onVideoReady: {
                withAnimation(.easeInOut(duration: 0.35)) {
                    isMotionVideoReady = true
                }
            }
        )
        .padding(.top, hasTallAnimatedCover ? 0 : MinidiscSpacing.xxl)
        .zIndex(1)

        AlbumMetadataSection(
            albumName: viewModel?.albumName ?? initialName,
            artistName: viewModel?.artistName,
            artistId: viewModel?.artistId,
            year: viewModel?.year,
            genre: viewModel?.genre,
            isLoading: viewModel == nil,
            isOffline: viewModel?.isOffline == true,
            isLossless: effectiveEnrichment?.isLossless ?? false,
            isAtmos: effectiveEnrichment?.isAtmos ?? false
        )
        .padding(.top, hasTallAnimatedCover ? MinidiscSpacing.s : MinidiscSpacing.xl)
        .zIndex(2)
    }

    @ViewBuilder
    private func trackListContent(songs: [DisplayableSong], vm: AlbumDetailViewModel) -> some View {
        let serverId = container?.serverState.activeServer?.id ?? UUID()
        if songs.isEmpty {
            if mode == .downloadedOnly {
                EmptyStateView(
                    systemImage: "arrow.down.circle.slash",
                    title: "No Downloaded Tracks",
                    subtitle: "No tracks from this album have been downloaded."
                )
            } else if let error = vm.error {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Unable to Load Album",
                    subtitle: LocalizedStringKey(error.displayMessage),
                    action: .init(label: "Retry") { Task { await vm.load() } }
                )
            } else {
                EmptyStateView(
                    systemImage: "music.note",
                    title: "No Tracks",
                    subtitle: "This album doesn't have any tracks yet."
                )
            }
        } else {
            AlbumSongRows(
                songs: songs,
                albumId: albumId,
                serverId: serverId,
                showArtists: shouldShowTrackArtists(in: songs),
                downloadingIds: vm.downloadingIds,
                titleColor: headerTextColor,
                secondaryColor: headerSecondaryColor,
                onTap: { index in
                    Task {
                        do {
                            try await container?.playerService.play(tracks: songs, startIndex: index)
                        } catch {
                            Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
                            if !UserFacingError.isCancellation(error) {
                                container?.toastService.showError(UserFacingError.from(error).displayMessage)
                            }
                        }
                    }
                },
                onDownload: (mode == .downloadedOnly || vm.isOffline || vm.isDownloadingAlbum) ? nil : { songId in
                    Task { await vm.downloadSong(id: songId) }
                },
                onRemoveDownload: { songId in
                    Task { await container?.toastService.perform { try await container?.downloadService.remove(songId: songId, serverId: serverId) } }
                },
                onAddToPlaylist: playlistAddition.present
            )

            AlbumReleaseInformationSection(
                releaseDate: vm.releaseDate,
                fallbackYear: vm.year,
                songCount: songs.count,
                totalDuration: songs.reduce(0) { $0 + $1.duration },
                releaseTypes: vm.releaseTypes,
                version: vm.version,
                recordLabels: vm.recordLabels,
                audioFormats: songs.compactMap(\.audioFormat),
                textColor: headerSecondaryColor
            )

            if case .full = mode, !vm.isOffline {
                if let artistId = vm.artistId,
                   let artistName = vm.artistName,
                   !artistName.isEmpty {
                    AlbumMoreByArtistSection(
                        artistId: artistId,
                        artistName: artistName,
                        currentAlbumId: albumId
                    )
                }

                AlbumYouMightAlsoLikeSection(albums: visibleRecommendedAlbums)
            }
        }
    }
}

// MARK: - Album presentation

struct AlbumDetailPalette {
    let backgroundTopColor: Color
    let backgroundBottomColor: Color
    let contentColor: Color
    let secondaryContentColor: Color
    let controlFillColor: Color
    let playLabelColor: Color
    let preferredContentScheme: ColorScheme?

    init(dominantColor: Color, appearance: ColorScheme) {
        guard dominantColor != .clear else {
            let background = Color(UIColor.systemBackground)
            backgroundTopColor = background
            backgroundBottomColor = background
            contentColor = .primary
            secondaryContentColor = .secondary
            controlFillColor = Color.primary.opacity(0.12)
            playLabelColor = .black
            preferredContentScheme = nil
            return
        }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(dominantColor).getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        ) else {
            let usesDarkContent = dominantColor.luminance > 0.6
            let foreground: Color = usesDarkContent ? .black : .white
            backgroundTopColor = dominantColor
            backgroundBottomColor = dominantColor
            contentColor = foreground
            secondaryContentColor = foreground.opacity(0.7)
            controlFillColor = foreground.opacity(0.12)
            playLabelColor = usesDarkContent ? .black : dominantColor
            preferredContentScheme = usesDarkContent ? .light : .dark
            return
        }

        let isChromatic = saturation >= 0.08
        let adjustedSaturation: Double
        let adjustedBrightness: Double

        if isChromatic {
            adjustedSaturation = min(
                max(Double(saturation) * (appearance == .dark ? 1.7 : 1.45), 0.46),
                0.96
            )
            adjustedBrightness = appearance == .dark
                ? min(max(Double(brightness) * 0.78, 0.28), 0.48)
                : min(max(Double(brightness) * 1.08, 0.52), 0.74)
        } else {
            // Keep monochrome artwork themed with a neutral grey background.
            adjustedSaturation = min(Double(saturation) * 1.2, 0.10)
            adjustedBrightness = appearance == .dark
                ? min(max(Double(brightness) * 0.52, 0.18), 0.30)
                : min(max(Double(brightness) * 0.78, 0.34), 0.48)
        }

        func themedColor(brightnessMultiplier: Double) -> Color {
            Color(
                hue: Double(hue),
                saturation: adjustedSaturation,
                brightness: min(max(adjustedBrightness * brightnessMultiplier, 0), 1)
            )
        }

        let topColor = themedColor(brightnessMultiplier: appearance == .dark ? 1.06 : 1.08)
        let bottomColor = themedColor(brightnessMultiplier: appearance == .dark ? 0.84 : 0.92)
        let usesDarkContent = topColor.luminance > 0.62 && bottomColor.luminance > 0.55
        let foreground: Color = usesDarkContent ? .black : .white

        backgroundTopColor = topColor
        backgroundBottomColor = bottomColor
        contentColor = foreground
        secondaryContentColor = foreground.opacity(0.7)
        controlFillColor = foreground.opacity(0.12)
        playLabelColor = themedColor(
            brightnessMultiplier: min(max(0.32 / max(adjustedBrightness, 0.01), 0.5), 1)
        )
        preferredContentScheme = usesDarkContent ? .light : .dark
    }
}

struct AlbumDetailPageBackground: View {
    let palette: AlbumDetailPalette

    var body: some View {
        LinearGradient(
            colors: [palette.backgroundTopColor, palette.backgroundBottomColor],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct AlbumArtworkSection: View {
    let coverArtId: String
    let coverImage: PlatformImage?
    let albumName: String
    var animatedURL: URL? = nil
    var isTall: Bool = true
    var isVideoReady: Bool = false
    var onVideoReady: (() -> Void)? = nil

    var body: some View {
        Group {
            if let animatedURL {
                if isTall {
                    GeometryReader { geo in
                        let width = geo.size.width
                        let tallHeight = width * 4.0 / 3.0

                        MotionArtworkView(
                            videoURL: animatedURL,
                            fallbackId: coverArtId,
                            fallbackImage: coverImage,
                            cornerRadius: 0,
                            aspectRatio: nil,
                            onReady: onVideoReady
                        )
                        .frame(width: width, height: tallHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 2.0 / 3.0),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .shadow(color: .clear, radius: 0, y: 0)
                    }
                    .frame(height: 440)
                    .id(animatedURL)
                } else {
                    MotionArtworkView(
                        videoURL: animatedURL,
                        fallbackId: coverArtId,
                        fallbackImage: coverImage,
                        cornerRadius: MinidiscCornerRadius.large,
                        aspectRatio: 1,
                        onReady: onVideoReady
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 340)
                    .minidiscCoverStyle(cornerRadius: MinidiscCornerRadius.large)
                    .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
                    .padding(.horizontal, 64)
                    .id(animatedURL)
                }
            } else {
                CoverArtView(
                    id: coverArtId,
                    size: 800,
                    tier: .hero,
                    cornerRadius: MinidiscCornerRadius.large,
                    initialImage: coverImage
                )
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 340)
                .minidiscCoverStyle(cornerRadius: MinidiscCornerRadius.large)
                .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
                .padding(.horizontal, 64)
            }
        }
        .accessibilityLabel(
            Text(
                "Artwork for \(albumName)",
                comment: "Accessibility label for the album cover; the variable is the album title."
            )
        )
    }
}

struct AlbumMetadataSection: View {
    let albumName: String
    let artistName: String?
    let artistId: String?
    let year: Int?
    let genre: String?
    let isLoading: Bool
    let isOffline: Bool
    var isLossless: Bool = false
    var isAtmos: Bool = false

    var body: some View {
        VStack(spacing: MinidiscSpacing.xs) {
            Text(albumName)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if isLoading {
                SkeletonBlock(width: 140, height: 18, cornerRadius: 4)
            } else if let artistName {
                if let artistId, !isOffline {
                    NavigationLink(value: HomeDestination.artist(ArtistID3(id: artistId, name: artistName))) {
                        Text(artistName)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(artistName)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if isLoading {
                SkeletonBlock(width: 100, height: 14, cornerRadius: 4)
                    .padding(.top, MinidiscSpacing.xs)
            } else {
                AlbumMetadataLine(
                    genre: genre,
                    year: year,
                    isLossless: isLossless,
                    isAtmos: isAtmos
                )
                .padding(.top, MinidiscSpacing.xs)
            }
        }
        .padding(.horizontal, MinidiscSpacing.xxl)
    }
}

private struct AlbumMetadataLine: View {
    let genre: String?
    let year: Int?
    var isLossless: Bool = false
    var isAtmos: Bool = false

    var body: some View {
        HStack(spacing: MinidiscSpacing.xs) {
            if let genre, !genre.isEmpty {
                Text(genre)
                    .lineLimit(1)
            }
            if genre?.isEmpty == false, year != nil {
                Text("·")
            }
            if let year {
                Text(String(year))
            }
            if isLossless {
                if (genre?.isEmpty == false) || year != nil {
                    Text("·")
                }
                AudioQualityBadge(.lossless, withBackground: false)
            }
            if isAtmos {
                if (genre?.isEmpty == false) || year != nil || isLossless {
                    Text("·")
                }
                AudioQualityBadge(.dolbyAtmos, withBackground: false)
            }
        }
        .font(.minidiscCaption)
        .foregroundStyle(.secondary)
    }
}

public struct DolbyLogoShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 18.338
        let scaleY = rect.height / 12.388
        let t = CGAffineTransform(scaleX: scaleX, y: scaleY)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))

        var left = Path()
        left.move(to: CGPoint(x: 0, y: 0))
        left.addLine(to: CGPoint(x: 2.736, y: 0))
        left.addCurve(to: CGPoint(x: 7.95, y: 6.194),
                      control1: CGPoint(x: 5.575, y: 0),
                      control2: CGPoint(x: 7.95, y: 2.767))
        left.addCurve(to: CGPoint(x: 2.736, y: 12.388),
                      control1: CGPoint(x: 7.95, y: 9.621),
                      control2: CGPoint(x: 5.576, y: 12.388))
        left.addLine(to: CGPoint(x: 0, y: 12.388))
        left.closeSubpath()

        var right = Path()
        right.move(to: CGPoint(x: 15.602, y: 0))
        right.addLine(to: CGPoint(x: 18.338, y: 0))
        right.addLine(to: CGPoint(x: 18.338, y: 12.388))
        right.addLine(to: CGPoint(x: 15.602, y: 12.388))
        right.addCurve(to: CGPoint(x: 10.388, y: 6.194),
                       control1: CGPoint(x: 12.763, y: 12.388),
                       control2: CGPoint(x: 10.388, y: 9.621))
        right.addCurve(to: CGPoint(x: 15.602, y: 0),
                       control1: CGPoint(x: 10.388, y: 2.767),
                       control2: CGPoint(x: 12.763, y: 0))
        right.closeSubpath()

        var combined = Path()
        combined.addPath(left)
        combined.addPath(right)
        return combined.applying(t)
    }
}

public struct DolbyLogoView: View {
    public init() {}

    public var body: some View {
        DolbyLogoShape()
            .fill()
    }
}

public struct LosslessWaveformView: View {
    public init() {}

    public var body: some View {
        Image("AppleLosslessLogo")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
    }
}

public struct AudioQualityBadge: View {
    public enum BadgeType {
        case lossless
        case dolbyAtmos
    }

    public let type: BadgeType
    public let title: String
    public var withBackground: Bool
    public var textWeight: Font.Weight?

    public init(_ type: BadgeType, title: String? = nil, withBackground: Bool = true, textWeight: Font.Weight? = nil) {
        self.type = type
        self.title = title ?? (type == .dolbyAtmos ? "Dolby Atmos" : "Lossless")
        self.withBackground = withBackground
        self.textWeight = textWeight
    }

    public init(title: String, withBackground: Bool = true, textWeight: Font.Weight? = nil) {
        if title.localizedCaseInsensitiveContains("atmos") || title.localizedCaseInsensitiveContains("dolby") {
            self.type = .dolbyAtmos
        } else {
            self.type = .lossless
        }
        self.title = title
        self.withBackground = withBackground
        self.textWeight = textWeight
    }

    @ViewBuilder
    public var body: some View {
        let content = HStack(alignment: .center, spacing: withBackground ? 4.5 : 3.5) {
            switch type {
            case .lossless:
                LosslessWaveformView()
                    .frame(
                        width: withBackground ? 16 : 14,
                        height: withBackground ? 9.6 : 8.4
                    )
            case .dolbyAtmos:
                DolbyLogoView()
                    .frame(
                        width: withBackground ? 14 : 13,
                        height: withBackground ? 9.5 : 8.8
                    )
            }
            let resolvedWeight: Font.Weight = textWeight ?? (withBackground ? .bold : .semibold)
            Text(title)
                .font(.system(size: withBackground ? 11.5 : 11, weight: resolvedWeight))
                .textCase(.none)
                .lineLimit(1)
        }

        if withBackground {
            content
                .padding(.horizontal, 7.5)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.18))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
        } else {
            content
        }
    }
}

private struct AlbumPlaybackActions: View {
    let albumId: String
    let songs: [DisplayableSong]
    let mode: AlbumDetailMode
    let viewModel: AlbumDetailViewModel?
    let downloadedAlbumTracks: [DownloadedTrack]
    let contentColor: Color
    let controlFillColor: Color
    let playLabelColor: Color
    @Binding var showDeleteAlert: Bool

    @Environment(\.appContainer) private var container

    var body: some View {
        VStack(spacing: MinidiscSpacing.m) {
            HStack(spacing: MinidiscSpacing.m) {
                Button {
                    HapticFeedback.medium.trigger()
                    Task {
                        guard !songs.isEmpty else { return }
                        await container?.toastService.perform { try await container?.playerService.play(tracks: songs.shuffled(), startIndex: 0) }
                    }
                } label: {
                    AlbumCircularActionLabel(
                        systemImage: "shuffle",
                        foregroundColor: contentColor,
                        backgroundColor: controlFillColor
                    )
                }
                .disabled(songs.isEmpty)
                .accessibilityLabel("Shuffle")

                PlayButton(
                    action: {
                        Task {
                            guard !songs.isEmpty else { return }
                            await container?.toastService.perform { try await container?.playerService.play(tracks: songs, startIndex: 0) }
                        }
                    },
                    isDisabled: songs.isEmpty,
                    accentColor: .white,
                    labelColor: playLabelColor,
                    height: 48
                )
                .frame(maxWidth: 220)

                AlbumDownloadActionButton(
                    albumId: albumId,
                    mode: mode,
                    viewModel: viewModel,
                    downloadedAlbumTracks: downloadedAlbumTracks,
                    contentColor: contentColor,
                    controlFillColor: controlFillColor,
                    showDeleteAlert: $showDeleteAlert
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, MinidiscSpacing.xxxxl)

            if mode == .full, let viewModel, viewModel.isDownloadingAlbum {
                AlbumDownloadProgress(
                    downloaded: downloadedAlbumTracks.count,
                    total: viewModel.songs.count
                )
            }
        }
    }
}

private struct AlbumCircularActionLabel: View {
    let systemImage: String
    let foregroundColor: Color
    let backgroundColor: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.minidiscCellTitle)
            .foregroundStyle(foregroundColor)
            .frame(width: 48, height: 48)
            .background(backgroundColor, in: Circle())
            .contentShape(Circle())
    }
}

private struct AlbumDownloadActionButton: View {
    let albumId: String
    let mode: AlbumDetailMode
    let viewModel: AlbumDetailViewModel?
    let downloadedAlbumTracks: [DownloadedTrack]
    let contentColor: Color
    let controlFillColor: Color
    @Binding var showDeleteAlert: Bool

    @Environment(\.appContainer) private var container

    private var state: AlbumDownloadControlState {
        if mode == .downloadedOnly {
            return downloadedAlbumTracks.isEmpty ? .unavailable : .removeDownloaded
        }
        guard let viewModel, !viewModel.isOffline else { return .unavailable }
        if viewModel.isDownloadingAlbum { return .cancel }

        switch AlbumDownloadState(songs: viewModel.songs) {
        case .notDownloaded:
            return viewModel.songs.isEmpty ? .unavailable : .download
        case .partiallyDownloaded:
            return .downloadMissing
        case .fullyDownloaded:
            return .removeDownloaded
        }
    }

    var body: some View {
        Button(action: performAction) {
            AlbumCircularActionLabel(
                systemImage: state.systemImage,
                foregroundColor: contentColor,
                backgroundColor: controlFillColor
            )
        }
        .disabled(state == .unavailable)
        .opacity(state == .unavailable ? 0.4 : 1)
        .accessibilityLabel(Text(actionLabel))
    }

    private var actionLabel: LocalizedStringResource {
        switch state {
        case .unavailable, .download: "Download Album"
        case .downloadMissing: "Download Missing Tracks"
        case .cancel: "Cancel Download"
        case .removeDownloaded: "Remove Download"
        }
    }

    private func performAction() {
        switch state {
        case .unavailable:
            break
        case .download:
            Task { await viewModel?.downloadAlbum() }
        case .downloadMissing:
            Task { await viewModel?.downloadMissingTracks() }
        case .cancel:
            Task { await viewModel?.cancelAlbumDownload() }
        case .removeDownloaded:
            if mode == .downloadedOnly {
                HapticFeedback.heavy.trigger()
                guard let container, let serverId = container.serverState.activeServer?.id else { return }
                Task {
                    await container.toastService.perform {
                        try await container.downloadService.remove(albumId: albumId, serverId: serverId)
                    }
                }
            } else {
                HapticFeedback.heavy.trigger()
                showDeleteAlert = true
            }
        }
    }
}

private struct AlbumDownloadProgress: View {
    let downloaded: Int
    let total: Int

    var body: some View {
        VStack(spacing: MinidiscSpacing.xs) {
            if downloaded == 0 {
                HStack(spacing: MinidiscSpacing.s) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Starting download…")
                }
            } else {
                ProgressView(value: Double(downloaded), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)
                    .tint(MinidiscColors.accent)
                    .frame(maxWidth: 280)
                Text("Downloading \(downloaded)/\(total) tracks")
            }
        }
        .font(.minidiscCaption)
        .foregroundStyle(.secondary)
        .frame(minHeight: 44)
    }
}

private struct AlbumTrackSkeletonRows: View {
    var body: some View {
        ForEach(0..<5, id: \.self) { _ in
            HStack(spacing: MinidiscSpacing.m) {
                SkeletonBlock(width: 20, height: 20, cornerRadius: 4)
                SkeletonBlock(width: 200, height: 16, cornerRadius: 4)
                Spacer()
                SkeletonBlock(width: 24, height: 16, cornerRadius: 4)
            }
            .padding(.vertical, MinidiscSpacing.s)
            .padding(.horizontal, MinidiscSpacing.l)
        }
    }
}

// MARK: - Download state

private nonisolated enum AlbumDownloadState {
    case notDownloaded
    case partiallyDownloaded
    case fullyDownloaded

    init(songs: [DisplayableSong]) {
        guard !songs.isEmpty else {
            self = .notDownloaded
            return
        }
        let downloaded = songs.lazy.filter(\.isDownloaded).count
        if downloaded == 0 {
            self = .notDownloaded
        } else if downloaded == songs.count {
            self = .fullyDownloaded
        } else {
            self = .partiallyDownloaded
        }
    }
}

private nonisolated enum AlbumDownloadControlState: Equatable {
    case unavailable
    case download
    case downloadMissing
    case cancel
    case removeDownloaded

    var systemImage: String {
        switch self {
        case .unavailable, .download, .downloadMissing:
            "arrow.down"
        case .cancel:
            "xmark"
        case .removeDownloaded:
            "trash"
        }
    }
}

// MARK: - Live download indicator rows

struct AlbumSongRows: View {
    let songs: [DisplayableSong]
    let showArtists: Bool
    let downloadingIds: Set<String>
    let titleColor: Color
    let secondaryColor: Color
    let onTap: (Int) -> Void
    let onDownload: ((String) -> Void)?
    let onRemoveDownload: ((String) -> Void)?
    let onAddToPlaylist: ((DisplayableSong) -> Void)?

    @Query private var downloadedTracks: [DownloadedTrack]
    @Query private var allFavorites: [FavoriteRecord]

    private var favoriteSongIds: Set<String> {
        Set(allFavorites.map(\.id))
    }

    init(songs: [DisplayableSong], albumId: String, serverId: UUID, showArtists: Bool = false, downloadingIds: Set<String> = [], titleColor: Color = .primary, secondaryColor: Color = .secondary, onTap: @escaping (Int) -> Void, onDownload: ((String) -> Void)? = nil, onRemoveDownload: ((String) -> Void)? = nil, onAddToPlaylist: ((DisplayableSong) -> Void)? = nil) {
        self.songs = songs
        self.showArtists = showArtists
        self.downloadingIds = downloadingIds
        self.titleColor = titleColor
        self.secondaryColor = secondaryColor
        self.onTap = onTap
        self.onDownload = onDownload
        self.onRemoveDownload = onRemoveDownload
        self.onAddToPlaylist = onAddToPlaylist
        let aid = albumId
        let sid = serverId
        _downloadedTracks = Query(
            filter: #Predicate<DownloadedTrack> { track in
                track.albumId == aid && track.serverId == sid
            }
        )
    }

    private var downloadedSongIds: Set<String> {
        Set(downloadedTracks.map(\.songId))
    }

    var body: some View {
        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
            let liveDownloaded = downloadedSongIds.contains(song.id)
            let liveSong = song.withDownloaded(liveDownloaded)
            let isDownloading = downloadingIds.contains(song.id)
            let downloadAction: (() -> Void)? = (liveDownloaded || isDownloading) ? nil : onDownload.map { action in { action(song.id) } }
            let removeAction: (() -> Void)? = liveDownloaded ? onRemoveDownload.map { action in { action(song.id) } } : nil
            VStack(spacing: 0) {
                SongRow(song: liveSong, index: index + 1, showArtist: showArtists, isFavorite: favoriteSongIds.contains("song:\(song.id)"), titleColor: titleColor, secondaryColor: secondaryColor, trailingAccessory: .menu, onDownload: downloadAction, onRemoveDownload: removeAction, isDownloading: isDownloading, onAddToPlaylist: onAddToPlaylist, onTap: { onTap(index) })
                    .padding(.vertical, 5)
                    .padding(.leading, MinidiscSpacing.xl)
                    .padding(.trailing, MinidiscSpacing.s)
                if index < songs.count - 1 {
                    Divider()
                        .overlay(titleColor.opacity(0.22))
                        .padding(.leading, MinidiscSpacing.xl + 36)
                }
            }
        }
    }
}

// MARK: - Release information

private struct AlbumReleaseInformationSection: View {
    let releaseDate: ItemDate?
    let fallbackYear: Int?
    let songCount: Int
    let totalDuration: TimeInterval
    let releaseTypes: [String]
    let version: String?
    let recordLabels: [String]
    let audioFormats: [String]
    let textColor: Color

    private var dateText: String? {
        guard let year = releaseDate?.year ?? fallbackYear else { return nil }
        guard let month = releaseDate?.month else { return String(year) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = releaseDate?.day ?? 1
        guard let date = calendar.date(from: components) else { return String(year) }

        if releaseDate?.day != nil {
            return date.formatted(.dateTime.day().month(.wide).year())
        }
        return date.formatted(.dateTime.month(.wide).year())
    }

    private var countAndDurationText: String? {
        guard songCount > 0 else { return nil }
        let count = String(localized: "\(songCount) songs")
        guard totalDuration > 0 else { return count }
        let duration = Duration.seconds(totalDuration).formatted(
            .units(allowed: [.hours, .minutes], width: .wide, maximumUnitCount: 2)
        )
        return "\(count), \(duration)"
    }

    private var descriptorText: String? {
        uniqueValues(
            releaseTypes.map { $0.localizedCapitalized }
                + [version].compactMap { $0 }
                + audioFormats.map { $0.uppercased() }
        )
        .joined(separator: " · ")
        .nilIfEmpty
    }

    private var labelText: String? {
        uniqueValues(recordLabels).joined(separator: " · ").nilIfEmpty
    }

    private var hasContent: Bool {
        dateText != nil || countAndDurationText != nil || descriptorText != nil || labelText != nil
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 3) {
                if let dateText {
                    Text(verbatim: dateText)
                }
                if let countAndDurationText {
                    Text(verbatim: countAndDurationText)
                }
                if let descriptorText {
                    Text(verbatim: descriptorText)
                }
                if let labelText {
                    Text(verbatim: labelText)
                }
            }
            .font(.footnote)
            .foregroundStyle(textColor.opacity(0.82))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MinidiscSpacing.l)
            .padding(.top, MinidiscSpacing.l)
            .accessibilityElement(children: .combine)
        }
    }

    private func uniqueValues(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { return nil }
            return trimmed
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - More by artist

/// A supplementary shelf, loaded independently so a slow artist lookup never delays the album or its tracks.
private struct AlbumMoreByArtistSection: View {
    let artistId: String
    let artistName: String
    let currentAlbumId: String

    @Environment(\.appContainer) private var container
    @State private var albums: [AlbumID3] = []

    private var sectionTitle: LocalizedStringResource {
        "More by \(artistName)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !albums.isEmpty {
                MinidiscShelf {
                    MinidiscCarouselHeaderLink(
                        sectionTitle,
                        itemCount: albums.count,
                        hasMore: true
                    ) {
                        ArtistDetailView(
                            artistId: artistId,
                            artistName: artistName,
                            coverArtId: nil
                        )
                    }
                } content: {
                    ForEach(albums) { album in
                        AlbumShelfCard(album: album)
                    }
                }
            }
        }
        .padding(.top, MinidiscSpacing.xxl)
        .padding(.bottom, MinidiscSpacing.xxl)
        .task(id: artistId) {
            await loadAlbums()
        }
    }

    private func loadAlbums() async {
        guard let container, container.serverState.isOnline else {
            albums = []
            return
        }

        do {
            let artist = try await container.libraryService.artist(id: artistId)
            try Task.checkCancellation()
            albums = Array(
                (artist.album ?? [])
                    .lazy
                    .filter { $0.id != currentAlbumId }
                    .prefix(MinidiscCarouselMetrics.previewLimit)
            )
        } catch is CancellationError {
            return
        } catch {
            albums = []
            Logger.library.warning(
                "Unable to load related albums for artist \(artistId, privacy: .public): \(error, privacy: .public)"
            )
        }
    }
}

// MARK: - You might also like

/// Album-level recommendations derived from Navidrome's similar-song graph.
/// Loading is independent from the primary album so an unavailable recommendation provider never delays playback.
private struct AlbumYouMightAlsoLikeSection: View {
    let albums: [AlbumID3]

    static let resultLimit = MinidiscCarouselMetrics.previewLimit * 2

    var body: some View {
        if !albums.isEmpty {
            MinidiscShelf {
                MinidiscCarouselHeaderLink(
                    "You Might Also Like",
                    itemCount: albums.count
                ) {
                    AlbumCarouselCollectionView(
                        "You Might Also Like",
                        albums: albums
                    )
                }
            } content: {
                ForEach(Array(albums.prefix(MinidiscCarouselMetrics.previewLimit))) { album in
                    AlbumShelfCard(album: album)
                }
            }
            .padding(.bottom, MinidiscSpacing.xxl)
        }
    }
}

// MARK: - Theme colour sheet

struct ThemeColorSheet: View {
    @Binding var color: Color
    let hasOverride: Bool
    var footerText: LocalizedStringKey = "Overrides the colour taken from the cover, here and anywhere else this appears."
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ColorPicker("Theme colour", selection: $color, supportsOpacity: false)
                } footer: {
                    Text(footerText)
                }
                if hasOverride {
                    Section {
                        Button("Reset to cover colour", systemImage: "arrow.uturn.backward", role: .destructive) {
                            onReset()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Theme colour")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(260)])
    }
}
