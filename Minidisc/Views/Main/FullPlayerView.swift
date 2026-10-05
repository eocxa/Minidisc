import SwiftUI
import SwiftData
import SwiftSonic
import OSLog

import AVKit

private enum PlayerSurface { case player, queue }

private struct PlayerThemeKey: Equatable {
    let coverId: String?
    let override: Color?
}

private struct LyricsLoadKey: Equatable {
    let trackID: String?
    let source: LyricsSource
}

private struct FullPlayerBackground: View {
    let colors: [Color]

    var body: some View {
        LinearGradient(colors: PlayerBackgroundPalette.colors(from: colors),
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

struct FullPlayerView: View {
    @Environment(\.appContainer) private var container
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var artworkNamespace: Namespace.ID? = nil
    var contentInsets: EdgeInsets = .init()
    var initialArtwork: PlayerArtworkSnapshot? = nil
    var dismissAction: () -> Void = {}

    @State private var vm = FullPlayerViewModel()
    @State private var playlistAddition = PlaylistAddition()
    @AppStorage("minidisc_player_show_lyrics") private var userWantsLyrics = false
    @State private var trackHasLyrics: Bool = true
    private var showLyrics: Bool {
        userWantsLyrics && trackHasLyrics && surface == .player && !(container?.playerState.isLiveStream ?? false)
    }
    @State private var surface: PlayerSurface = .player
    @State private var lyricsViewModel: LyricsViewModel?
    @State private var trackSwipe = TrackSwipeInteraction()
    @State private var currentTrackEnrichment: NowLocalEnrichment?
    @State private var isMotionArtworkReady = false
    @State private var areLyricsControlsHidden = false
    @State private var lyricsInactivityTask: Task<Void, Never>?
    @State private var lastActivityTime: Date = Date()
    @State private var previousTrack: DisplayableSong?
    @Namespace private var morphNS

    private var effectiveTrackEnrichment: NowLocalEnrichment? {
        let track = container?.playerState.currentTrack
        if let currentTrackEnrichment {
            if track?.albumName == nil || currentTrackEnrichment.album == nil || NowLocalService.albumsMatch(currentTrackEnrichment.album, track?.albumName) {
                return currentTrackEnrichment
            }
        }
        let cached = NowLocalService.shared.cachedEnrichment(
            album: track?.albumName,
            artist: track?.artist,
            title: track?.title
        ) ?? NowLocalService.shared.cachedEnrichment(
            album: track?.albumName,
            artist: nil,
            title: nil
        )
        if let cached,
           let enAlb = cached.album,
           let curAlb = track?.albumName,
           !enAlb.isEmpty && !curAlb.isEmpty && !NowLocalService.albumsMatch(enAlb, curAlb) {
            return nil
        }
        return cached
    }

    private var isDataSaverEnabled: Bool {
        UserDefaults.standard.bool(forKey: "minidisc_data_saver_enabled")
    }

    private var isCellularRestricted: Bool {
        let disabledOnCellular = UserDefaults.standard.bool(forKey: "minidisc_motion_artwork_cellular_disabled")
        let isCellular = container?.serverState.isCellular ?? MotionArtworkCache.shared.isCellular
        return disabledOnCellular && isCellular
    }

    private var resolvedAnimatedTallURL: URL? {
        guard !UserDefaults.standard.bool(forKey: "minidisc_motion_artwork_disabled") else { return nil }
        guard !showLyrics else { return nil }
        guard let url = NowLocalService.shared.resolveArtworkURL(
            path: effectiveTrackEnrichment?.animatedTallUrl,
            activeServerBaseURL: container?.serverState.activeServer?.baseURL
        ) else { return nil }
        if (isDataSaverEnabled || isCellularRestricted) && MotionArtworkCache.shared.cachedURL(for: url) == nil {
            return nil
        }
        return url
    }

    private var resolvedAnimatedSquareURL: URL? {
        guard !UserDefaults.standard.bool(forKey: "minidisc_motion_artwork_disabled") else { return nil }
        guard !showLyrics else { return nil }
        guard let url = NowLocalService.shared.resolveArtworkURL(
            path: effectiveTrackEnrichment?.animatedSquareUrl,
            activeServerBaseURL: container?.serverState.activeServer?.baseURL
        ) else { return nil }
        if (isDataSaverEnabled || isCellularRestricted) && MotionArtworkCache.shared.cachedURL(for: url) == nil {
            return nil
        }
        return url
    }

    private var resolvedAnimatedCoverURL: URL? {
        resolvedAnimatedTallURL ?? resolvedAnimatedSquareURL
    }

    private var hasTallMotionCanvas: Bool {
        resolvedAnimatedTallURL != nil
    }

    private var hasMotionCanvas: Bool {
        hasTallMotionCanvas
    }

    private var isCompact: Bool {
        showLyrics || (surface == .queue && !(container?.playerState.isLiveStream ?? false))
    }

    // MARK: - Player layout

    private static let playerCoverHPadding: CGFloat = MinidiscSpacing.xxl
    private static let playerHorizontalPadding: CGFloat = MinidiscSpacing.xxxl
    private static let playerTopGap: CGFloat = 36
    private static let playerCoverToTitleGap: CGFloat = MinidiscSpacing.xl
    private static let playerControlsSpacing: CGFloat = MinidiscSpacing.xl

    var body: some View {
        @Bindable var playlistAddition = playlistAddition

        if let playerState = container?.playerState {
            let lyricsSource = container?.lyricsSettings.source ?? .automatic
            let lyricsLoadKey = LyricsLoadKey(
                trackID: playerState.currentTrack?.id,
                source: lyricsSource
            )
            let themeCoverId: String? = playerState.isLiveStream
                ? playerState.currentRadio?.coverArt
                : (playerState.currentTrack?.coverArtId ?? playerState.currentTrack?.id)
            content(playerState)
                .task(id: PlayerThemeKey(coverId: themeCoverId, override: colorExtractor.colorOverride(for: themeCoverId ?? ""))) {
                    await vm.updateColors(for: themeCoverId, colorExtractor: colorExtractor, container: container, reduceMotion: reduceMotion)
                }
                .task(id: lyricsLoadKey) {
                    if playerState.currentTrack?.isLocalFile == true {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            trackHasLyrics = false
                        }
                        lyricsViewModel = nil
                        return
                    }
                    guard let track = playerState.currentTrack, !track.isLocalFile,
                          let serverId = container?.serverState.activeServer?.id,
                          let lyricsService = container?.lyricsService,
                          let playerService = container?.playerService else {
                        lyricsViewModel = nil
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            trackHasLyrics = false
                        }
                        return
                    }

                    // Check fast cache first
                    let cachedEnrichment = NowLocalService.shared.cachedEnrichment(
                        album: track.albumName,
                        artist: track.artist,
                        title: track.title
                    )
                    if let cachedEnrichment {
                        if cachedEnrichment.lyricsUrl != nil && cachedEnrichment.lyricsType != "none" {
                            if !trackHasLyrics {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                    trackHasLyrics = true
                                }
                            }
                        }
                    }

                    let newVM = LyricsViewModel(
                        track: track,
                        serverId: serverId,
                        source: lyricsSource,
                        lyricsService: lyricsService,
                        playerService: playerService,
                        playerState: playerState,
                        activeServerBaseURL: container?.serverState.activeServer?.baseURL
                    )
                    newVM.setVisible(showLyrics)
                    lyricsViewModel = newVM
                    await newVM.load()

                    guard !Task.isCancelled else { return }

                    let available = newVM.hasLyrics
                    if trackHasLyrics != available {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            trackHasLyrics = available
                        }
                    }
                }
                .task(id: playerState.currentTrack?.id) {
                    guard let track = playerState.currentTrack else {
                        currentTrackEnrichment = nil
                        previousTrack = nil
                        isMotionArtworkReady = false
                        return
                    }

                    let sameAlbum: Bool = {
                        if let prev = previousTrack {
                            if let aid = track.albumId, let paid = prev.albumId, !aid.isEmpty && !paid.isEmpty && aid == paid {
                                return true
                            }
                            if NowLocalService.albumsMatch(track.albumName, prev.albumName) {
                                return true
                            }
                        }
                        if let cur = currentTrackEnrichment?.album, NowLocalService.albumsMatch(track.albumName, cur) {
                            return true
                        }
                        return false
                    }()

                    let existingTall = currentTrackEnrichment?.animatedTallUrl
                    let existingSquare = currentTrackEnrichment?.animatedSquareUrl

                    if !sameAlbum {
                        isMotionArtworkReady = false
                        currentTrackEnrichment = nil
                    }

                    var cached = NowLocalService.shared.cachedEnrichment(
                        album: track.albumName,
                        artist: track.artist,
                        title: track.title
                    ) ?? NowLocalService.shared.cachedEnrichment(
                        album: track.albumName,
                        artist: nil,
                        title: nil
                    )

                    // Ensure cached enrichment strictly belongs to this album
                    if let c = cached,
                       let cAlb = c.album,
                       let curAlb = track.albumName,
                       !cAlb.isEmpty && !curAlb.isEmpty && !NowLocalService.albumsMatch(cAlb, curAlb) {
                        cached = nil
                    }

                    if sameAlbum && (cached == nil || (cached?.animatedTallUrl == nil && cached?.animatedSquareUrl == nil)) {
                        if existingTall != nil || existingSquare != nil {
                            cached = NowLocalEnrichment(
                                found: cached?.found ?? true,
                                trackId: cached?.trackId,
                                title: cached?.title,
                                artist: cached?.artist ?? track.artist,
                                album: cached?.album ?? track.albumName,
                                hasAnimatedArtwork: true,
                                animatedSquareUrl: existingSquare ?? cached?.animatedSquareUrl,
                                animatedTallUrl: existingTall ?? cached?.animatedTallUrl,
                                isAtmos: cached?.isAtmos,
                                isLossless: cached?.isLossless,
                                lyricsUrl: cached?.lyricsUrl,
                                lyricsType: cached?.lyricsType
                            )
                        }
                    }

                    currentTrackEnrichment = cached

                    var enrichment = await NowLocalService.shared.fetchEnrichment(
                        album: track.albumName,
                        artist: track.artist,
                        title: track.title,
                        activeServerBaseURL: container?.serverState.activeServer?.baseURL
                    )
                    // Validate album matches!
                    if let e = enrichment,
                       let eAlb = e.album,
                       let curAlb = track.albumName,
                       !eAlb.isEmpty && !curAlb.isEmpty && !NowLocalService.albumsMatch(eAlb, curAlb) {
                        enrichment = nil
                    }

                    if (enrichment?.animatedTallUrl == nil && enrichment?.animatedSquareUrl == nil), let album = track.albumName, !album.isEmpty {
                        var albumEnrichment = await NowLocalService.shared.fetchEnrichment(
                            album: album,
                            artist: track.artist,
                            title: nil,
                            activeServerBaseURL: container?.serverState.activeServer?.baseURL
                        )
                        if let ae = albumEnrichment,
                           let aeAlb = ae.album,
                           !aeAlb.isEmpty && !NowLocalService.albumsMatch(aeAlb, album) {
                            albumEnrichment = nil
                        }
                        if albumEnrichment == nil {
                            albumEnrichment = await NowLocalService.shared.fetchEnrichment(
                                album: album,
                                artist: nil,
                                title: nil,
                                activeServerBaseURL: container?.serverState.activeServer?.baseURL
                            )
                            if let ae = albumEnrichment,
                               let aeAlb = ae.album,
                               !aeAlb.isEmpty && !NowLocalService.albumsMatch(aeAlb, album) {
                                albumEnrichment = nil
                            }
                        }
                        if let albumEnrichment {
                            enrichment = NowLocalEnrichment(
                                found: true,
                                trackId: enrichment?.trackId ?? albumEnrichment.trackId,
                                title: enrichment?.title,
                                artist: enrichment?.artist ?? track.artist,
                                album: enrichment?.album ?? album,
                                hasAnimatedArtwork: true,
                                animatedSquareUrl: enrichment?.animatedSquareUrl ?? albumEnrichment.animatedSquareUrl,
                                animatedTallUrl: albumEnrichment.animatedTallUrl ?? enrichment?.animatedTallUrl,
                                isAtmos: enrichment?.isAtmos ?? albumEnrichment.isAtmos,
                                isLossless: enrichment?.isLossless ?? albumEnrichment.isLossless,
                                lyricsUrl: enrichment?.lyricsUrl ?? albumEnrichment.lyricsUrl,
                                lyricsType: enrichment?.lyricsType ?? albumEnrichment.lyricsType
                            )
                        }
                    }

                    // Fallback for tracks played from outside (search, playlists, unknown album)
                    if enrichment?.animatedTallUrl == nil && enrichment?.animatedSquareUrl == nil {
                        if !track.title.isEmpty {
                            let trackDiscover = await NowLocalService.shared.fetchEnrichment(
                                album: nil,
                                artist: track.artist,
                                title: track.title,
                                activeServerBaseURL: container?.serverState.activeServer?.baseURL
                            )
                            if let td = trackDiscover, td.animatedTallUrl != nil || td.animatedSquareUrl != nil {
                                enrichment = NowLocalEnrichment(
                                    found: true,
                                    trackId: enrichment?.trackId ?? td.trackId,
                                    title: enrichment?.title ?? td.title,
                                    artist: enrichment?.artist ?? td.artist,
                                    album: enrichment?.album ?? td.album,
                                    hasAnimatedArtwork: true,
                                    animatedSquareUrl: td.animatedSquareUrl,
                                    animatedTallUrl: td.animatedTallUrl,
                                    isAtmos: enrichment?.isAtmos ?? td.isAtmos,
                                    isLossless: enrichment?.isLossless ?? td.isLossless,
                                    lyricsUrl: enrichment?.lyricsUrl ?? td.lyricsUrl,
                                    lyricsType: enrichment?.lyricsType ?? td.lyricsType
                                )
                            }
                        }
                    }

                    // If sameAlbum and track lookup lacked video, inherit from existing video!
                    if sameAlbum && (existingTall != nil || existingSquare != nil) {
                        if enrichment == nil {
                            enrichment = cached
                        }
                        if let e = enrichment, e.animatedTallUrl == nil && e.animatedSquareUrl == nil {
                            enrichment = NowLocalEnrichment(
                                found: e.found,
                                trackId: e.trackId,
                                title: e.title,
                                artist: e.artist,
                                album: e.album,
                                hasAnimatedArtwork: true,
                                animatedSquareUrl: existingSquare,
                                animatedTallUrl: existingTall,
                                isAtmos: e.isAtmos,
                                isLossless: e.isLossless,
                                lyricsUrl: e.lyricsUrl,
                                lyricsType: e.lyricsType
                            )
                        }
                    }

                    if let enrichment {
                        var keysToStore = [
                            "\(track.albumName ?? "")_\(track.artist ?? "")_\(track.title)"
                        ]
                        if let an = track.albumName, !an.isEmpty {
                            keysToStore.append("\(an)_\(track.artist ?? "")_")
                            keysToStore.append("\(an)__")
                            let cleanAn = NowLocalService.cleanMetadata(an)
                            if cleanAn != an && !cleanAn.isEmpty {
                                keysToStore.append("\(cleanAn)_\(track.artist ?? "")_")
                                keysToStore.append("\(cleanAn)__")
                            }
                        }
                        NowLocalService.shared.storeCachedEnrichment(
                            enrichment,
                            forKeys: keysToStore
                        )
                        withAnimation(.easeInOut(duration: 0.35)) {
                            currentTrackEnrichment = enrichment
                        }
                    } else if !sameAlbum {
                        currentTrackEnrichment = nil
                    }
                    previousTrack = track
                }
                .sheet(item: $playlistAddition.request) { request in
                    AddToPlaylistSheet(request: request)
                }
                .environment(playlistAddition)
        }
    }

    @ViewBuilder
    private func content(_ playerState: PlayerState) -> some View {
        let coverArtId = playerState.isLiveStream
            ? (playerState.currentRadio?.coverArt ?? "")
            : (playerState.currentTrack?.coverArtId ?? playerState.currentTrack?.id ?? "")
        // Use the memoized color on the first frame while the view model catches up.
        let colors = colorExtractor.cachedBackgroundColors(for: coverArtId)
            ?? (vm.coverArtID == coverArtId ? vm.backgroundColors
                : Array(repeating: colorExtractor.cachedColor(for: coverArtId) ?? .black, count: 4))
        let showingQueue = isQueueVisible(playerState)

        surfaceStack(playerState, coverArtId: coverArtId, showingQueue: showingQueue)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .minidiscContentWidth()
            .padding(EdgeInsets(
                top: (hasMotionCanvas && !isCompact) ? 0 : contentInsets.top,
                leading: (hasMotionCanvas && !isCompact) ? 0 : contentInsets.leading,
                bottom: contentInsets.bottom,
                trailing: (hasMotionCanvas && !isCompact) ? 0 : contentInsets.trailing
            ))
            .environment(\.colorScheme, .dark)
            .environment(\.minidiscPlayingAccent, MinidiscColors.accent)
            .onAppear {
                if showLyrics {
                    areLyricsControlsHidden = false
                    startInactivityTimer()
                }
            }
            .onDisappear {
                lyricsInactivityTask?.cancel()
            }
            .onChange(of: showLyrics, initial: true) { _, isShowing in
                lyricsViewModel?.setVisible(isShowing)
                if isShowing {
                    areLyricsControlsHidden = false
                    startInactivityTimer()
                } else {
                    lyricsInactivityTask?.cancel()
                    areLyricsControlsHidden = false
                }
            }
            .onChange(of: lyricsViewModel?.hasLyrics) { _, _ in
                guard let vm = lyricsViewModel, !vm.isLoading else { return }
                if trackHasLyrics != vm.hasLyrics {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        trackHasLyrics = vm.hasLyrics
                    }
                }
            }
            .onChange(of: surface) { _, newSurface in
                if newSurface == .queue {
                    lyricsInactivityTask?.cancel()
                    areLyricsControlsHidden = false
                }
            }
            .onChange(of: playerState.currentTrack?.id) { _, _ in
                if showLyrics {
                    userDidInteract()
                }
            }
            .onChange(of: lyricsViewModel?.isUserScrolling) { _, isScrolling in
                if isScrolling == true {
                    userDidInteract()
                }
            }
        .background {
            FullPlayerBackground(colors: colors)
                .contentShape(Rectangle())
                .onTapGesture {
                    userDidInteract()
                }
        }
    }

    @ViewBuilder
    private func surfaceStack(
        _ playerState: PlayerState,
        coverArtId: String,
        showingQueue: Bool
    ) -> some View {
        let isCompact = showLyrics || showingQueue

        VStack(spacing: 0) {
            VStack(spacing: 0) {
                flowGap(isCompact ? 72 : (hasMotionCanvas ? 0 : 40))

                ZStack {
                    if showLyrics {
                        flowingLyricsContent(playerState)
                            .transition(.opacity)
                    } else if showingQueue {
                        flowingQueueContent(playerState)
                            .transition(.opacity)
                    }

                    // Keep the cover mounted across player, queue and lyrics for matched geometry.
                    flowingCover(playerState, coverArtId: coverArtId, isSource: !isCompact)
                        .allowsHitTesting(!isCompact)
                        .padding(.horizontal, isCompact || hasMotionCanvas ? 0 : Self.playerCoverHPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !isCompact {
                    flowGap(Self.playerCoverToTitleGap)

                    TrackInfoSection(
                        playerState: playerState,
                        container: container,
                        contentColor: vm.contentColor,
                        secondaryContentColor: vm.secondaryContentColor,
                        trackSwipe: trackSwipe
                    )
                    .padding(.horizontal, Self.playerHorizontalPadding)
                }

                if !showLyrics || !areLyricsControlsHidden {
                    VStack(spacing: 0) {
                        if !playerState.isLiveStream {
                            ScrubberView(
                                playerState: playerState,
                                playerService: container?.playerService,
                                contentColor: vm.contentColor,
                                secondaryContentColor: vm.secondaryContentColor,
                                isLossless: effectiveTrackEnrichment?.isLossless ?? false,
                                isAtmos: effectiveTrackEnrichment?.isAtmos ?? false
                            )
                            .padding(.horizontal, Self.playerHorizontalPadding)
                            .padding(.top, MinidiscSpacing.m)
                            .disabled(!playerState.isPlaybackAvailable)
                            .opacity(playerState.isPlaybackAvailable ? 1.0 : 0.4)
                        }

                        PlaybackControlsView(
                            playerState: playerState,
                            playerService: container?.playerService,
                            isPlaybackAvailable: playerState.isPlaybackAvailable,
                            keepsPauseIcon: trackSwipe.keepsPauseIcon,
                            contentColor: vm.contentColor
                        )
                        .padding(.top, Self.playerControlsSpacing)

                        if dynamicTypeSize < .accessibility1 {
                            VolumeSection(contentColor: vm.contentColor, secondaryContentColor: vm.secondaryContentColor)
                                .padding(.horizontal, Self.playerHorizontalPadding)
                                .padding(.top, Self.playerControlsSpacing)
                        }

                        flowGap(isCompact ? 24 : 40)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if showLyrics && areLyricsControlsHidden {
                    flowGap(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: showLyrics)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: surface)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: areLyricsControlsHidden)
            .animation(.easeInOut(duration: 0.4), value: hasMotionCanvas)

            if !showLyrics || !areLyricsControlsHidden {
                BottomToolbar(
                    userWantsLyrics: $userWantsLyrics,
                    isLyricsShowing: showLyrics,
                    hasLyrics: trackHasLyrics,
                    surface: $surface,
                    isLiveStream: playerState.isLiveStream,
                    secondaryContentColor: vm.secondaryContentColor,
                    accentColor: MinidiscColors.accent,
                    playerState: playerState
                )
                .padding(.top, MinidiscSpacing.s)
                .padding(.bottom, MinidiscSpacing.l)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .overlay(alignment: .top) {
            topBar
        }
        .overlay(alignment: .bottom) {
            if showLyrics && areLyricsControlsHidden {
                Color.black.opacity(0.001)
                    .frame(maxWidth: .infinity)
                    .frame(height: 250)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        userDidInteract()
                    }
            }
        }
    }

    private func flowGap(_ floor: CGFloat) -> some View {
        Color.clear.frame(minHeight: floor, maxHeight: floor)
    }

    private func flowingCover(_ playerState: PlayerState, coverArtId: String, isSource: Bool) -> some View {
        GeometryReader { geo in
            let artworkSide = min(geo.size.width, geo.size.height)
            let isCanvas = hasMotionCanvas && isSource && !showLyrics

            let effectiveAnimatedURL = resolvedAnimatedCoverURL
            let canvasWidth = isCanvas ? geo.size.width : artworkSide
            let canvasHeight = isCanvas ? max(geo.size.height, geo.size.width * 4.0 / 3.0) : artworkSide

            Group {
                if let animatedURL = effectiveAnimatedURL, isSource, !showLyrics {
                    MotionArtworkView(
                        videoURL: animatedURL,
                        fallbackId: coverArtId,
                        fallbackImage: initialArtwork?.id == coverArtId ? initialArtwork?.image : nil,
                        cornerRadius: isCanvas ? 0 : MinidiscCornerRadius.large,
                        isPaused: false,
                        aspectRatio: isCanvas ? nil : 1,
                        onReady: {
                            if !isMotionArtworkReady {
                                withAnimation(.easeInOut(duration: 0.4)) {
                                    isMotionArtworkReady = true
                                }
                            }
                        }
                    )
                    .frame(
                        width: canvasWidth,
                        height: canvasHeight
                    )
                    .clipped()
                    .mask {
                        if isCanvas {
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 0.65),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        } else {
                            Color.black
                        }
                    }
                } else {
                    CoverArtView(id: coverArtId, size: 1000,
                                 initialImage: initialArtwork?.id == coverArtId ? initialArtwork?.image : nil)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: isSource ? MinidiscCornerRadius.large : MinidiscCornerRadius.standard,
                                style: .continuous
                            )
                        )
                }
            }
            .matchedGeometryEffect(id: "playerArtwork", in: artworkNamespace ?? morphNS, isSource: isSource)
            .frame(
                width: isSource ? canvasWidth : nil,
                height: isSource ? canvasHeight : nil
            )
            .shadow(
                color: isCanvas ? .clear : (isSource ? Color.black.opacity(0.28) : Color.black.opacity(0.12)),
                radius: isSource ? 18 : 6,
                y: isSource ? 10 : 3
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isCanvas ? .top : .center)
            .trackSwipeGesture(
                interaction: trackSwipe,
                playerState: playerState,
                playerService: container?.playerService,
                reduceMotion: reduceMotion,
                isEnabled: isSource && playerState.isPlaybackAvailable && !playerState.isLiveStream
            )
            .accessibilityIdentifier("player.artwork")
        }
    }

    private func flowingLyricsContent(_ playerState: PlayerState) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: MinidiscSpacing.m) {
                // Invisible endpoint for the cover's matched-geometry transition.
                Color.clear
                    .frame(width: 56, height: 56)
                    .matchedGeometryEffect(id: "playerArtwork", in: artworkNamespace ?? morphNS, isSource: true)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            userWantsLyrics = false
                        }
                    }

                TrackInfoSection(
                    playerState: playerState,
                    container: container,
                    contentColor: vm.contentColor,
                    secondaryContentColor: vm.secondaryContentColor,
                    compact: true
                )
            }
            .padding(.horizontal, MinidiscSpacing.l)
            .padding(.top, MinidiscSpacing.s)

            if let lyricsVM = lyricsViewModel {
                LyricsView(viewModel: lyricsVM, areControlsHidden: areLyricsControlsHidden)
                    .id(ObjectIdentifier(lyricsVM))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 0)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.02),
                                .init(color: .black, location: 0.92),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func flowingQueueContent(_ playerState: PlayerState) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: MinidiscSpacing.m) {
                // Invisible endpoint for the cover's matched-geometry transition.
                Color.clear
                    .frame(width: 56, height: 56)
                    .matchedGeometryEffect(id: "playerArtwork", in: artworkNamespace ?? morphNS, isSource: true)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            surface = .player
                        }
                    }

                TrackInfoSection(
                    playerState: playerState,
                    container: container,
                    contentColor: vm.contentColor,
                    secondaryContentColor: vm.secondaryContentColor,
                    compact: true
                )
            }
            .padding(.horizontal, MinidiscSpacing.l)
            .padding(.top, MinidiscSpacing.s)

            queuePills(playerState)
                .padding(.horizontal, MinidiscSpacing.l)
                .padding(.vertical, MinidiscSpacing.m)

            InlineQueueList(
                playerState: playerState,
                contentColor: vm.contentColor,
                secondaryContentColor: vm.secondaryContentColor,
                loadArtwork: true
            )
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)

        }
    }

    // MARK: - Lyrics Inactivity Timer

    private func userDidInteract() {
        guard showLyrics else {
            if areLyricsControlsHidden { areLyricsControlsHidden = false }
            lyricsInactivityTask?.cancel()
            return
        }
        let now = Date()
        if areLyricsControlsHidden {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                areLyricsControlsHidden = false
            }
        }
        if now.timeIntervalSince(lastActivityTime) > 0.4 || lyricsInactivityTask == nil {
            lastActivityTime = now
            startInactivityTimer()
        }
    }

    private func startInactivityTimer() {
        lyricsInactivityTask?.cancel()
        guard showLyrics else { return }
        lyricsInactivityTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, showLyrics else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                areLyricsControlsHidden = true
            }
        }
    }

    // MARK: - Surfaces

    private func isQueueVisible(_ playerState: PlayerState) -> Bool {
        surface == .queue && !playerState.isLiveStream
    }

    private func queuePills(_ playerState: PlayerState) -> some View {
        HStack(spacing: MinidiscSpacing.s) {
            queuePill(systemImage: "shuffle", isActive: playerState.isShuffled,
                      label: playerState.isShuffled ? "Shuffle On" : "Shuffle Off") {
                Task { await container?.playerService.toggleShuffle() }
            }
            queuePill(systemImage: playerState.repeatMode.systemImage, isActive: playerState.repeatMode != .off,
                      label: "Repeat") {
                Task { await container?.playerService.setRepeatMode(playerState.repeatMode.next) }
            }
            queuePill(systemImage: "infinity", isActive: playerState.isAutoExtendEnabled && playerState.currentTrack?.isLocalFile != true,
                      label: "Auto-extend with Smart Shuffle") {
                Task { await container?.playerService.setAutoExtendEnabled(!playerState.isAutoExtendEnabled) }
            }
            .disabled(playerState.currentTrack?.isLocalFile == true)
        }
    }

    private func queuePill(systemImage: String, isActive: Bool, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        // The fixed active color keeps 4.7:1 contrast with its white glyph.
        return Button {
            HapticFeedback.light.trigger()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(isActive ? Color.white : vm.secondaryContentColor)
                .frame(height: 24)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MinidiscSpacing.s)
                .background {
                    Capsule().fill(isActive ? MinidiscColors.AccentRamp.v500 : vm.contentColor.opacity(0.12))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var topBar: some View {
        Button {
            dismissAction()
        } label: {
            Capsule()
                .fill(vm.contentColor.opacity(0.4))
                .frame(width: 60, height: 5)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .top)
                .contentShape(Rectangle())
        }
        .padding(.top, (hasMotionCanvas && !isCompact) ? (contentInsets.top + 8) : 8)
        .buttonStyle(.plain)
        .accessibilityLabel("Close player")
    }

}

// MARK: - Track info section (own @Query for reactive favorite state)

private struct TrackInfoSection: View {
    let playerState: PlayerState
    let container: AppContainer?
    let contentColor: Color
    let secondaryContentColor: Color
    var compact: Bool = false
    var trackSwipe: TrackSwipeInteraction?

    @Query private var favoriteMatches: [FavoriteRecord]
    @Environment(PlaylistAddition.self) private var playlistAddition
    @State private var showAlbumSheet = false
    @State private var shareRequest: DisplayableSong?
    @State private var preparedShare: PreparedTrackShare?
    @State private var trackInformation: DisplayableSong?

    init(
        playerState: PlayerState,
        container: AppContainer?,
        contentColor: Color,
        secondaryContentColor: Color,
        compact: Bool = false,
        trackSwipe: TrackSwipeInteraction? = nil
    ) {
        self.playerState = playerState
        self.container = container
        self.contentColor = contentColor
        self.secondaryContentColor = secondaryContentColor
        self.compact = compact
        self.trackSwipe = trackSwipe
        let cid = "song:\(playerState.currentTrack?.id ?? "")"
        _favoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == cid })
    }

    private var isFavorite: Bool { !favoriteMatches.isEmpty }
    private var isOnline: Bool { container?.serverState.isOnline == true }

    var body: some View {
        HStack(alignment: .top, spacing: MinidiscSpacing.m) {
            trackMetadata
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

            HStack(spacing: MinidiscSpacing.s) {
                if !playerState.isLiveStream {
                    Button {
                        toggleFavorite()
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(contentColor)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isOnline || playerState.currentTrack == nil || playerState.currentTrack?.isLocalFile == true)
                    .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                }

                Menu {
                    if !playerState.isLiveStream {
                        ControlGroup {
                            if let track = playerState.currentTrack {
                                Button {
                                    shareRequest = track
                                } label: {
                                    Label("Share", systemImage: "square.and.arrow.up.fill")
                                }
                                .disabled(shareRequest != nil || playerState.currentTrack?.isLocalFile == true)
                            }

                            if isFavorite {
                                Button("Undo", systemImage: "star.slash.fill") {
                                    toggleFavorite()
                                }
                                .disabled(!isOnline || playerState.currentTrack == nil || playerState.currentTrack?.isLocalFile == true)
                            } else {
                                Button("Favorite", systemImage: "star.fill") {
                                    toggleFavorite()
                                }
                                .disabled(!isOnline || playerState.currentTrack == nil || playerState.currentTrack?.isLocalFile == true)
                            }
                        }

                        Divider()
                        Button {
                            goToAlbum()
                        } label: {
                            Label("Go to Album", systemImage: "music.note.square.stack")
                            if let albumName = playerState.currentTrack?.albumName, !albumName.isEmpty {
                                Text(albumName)
                            }
                        }
                        .disabled(playerState.currentTrack?.albumName == nil || !isOnline)
                        Button {
                            goToArtist()
                        } label: {
                            Label("Go to Artist", systemImage: "music.mic")
                            if let artist = playerState.currentTrack?.artist, !artist.isEmpty {
                                Text(artist)
                            }
                        }
                        .disabled(playerState.currentTrack?.artist == nil || !isOnline || playerState.currentTrack?.isLocalFile == true)
                        Button("Get Info", systemImage: "info.circle") {
                            trackInformation = playerState.currentTrack
                        }
                        .disabled(playerState.currentTrack == nil)
                        Divider()
                        Button("Save Queue as Playlist", systemImage: "text.badge.plus") {
                            playlistAddition.present(songs: playerState.queue, createsPlaylist: true)
                        }
                        .disabled(!isOnline || playerState.queue.isEmpty || playerState.queue.contains(where: \.isLocalFile))
                        .accessibilityIdentifier("queue.savePlaylist")
                        Button("Add to Playlist...", systemImage: "music.note.list") {
                            if let track = playerState.currentTrack {
                                playlistAddition.present(track)
                            }
                        }
                        .disabled(!isOnline || playerState.currentTrack == nil || playerState.currentTrack?.isLocalFile == true)
                        Divider()
                        Button("Instant Mix", systemImage: instantMixSymbol) {
                            guard let track = playerState.currentTrack else { return }
                            startInstantMix(from: .song(id: track.id), using: container, startingWith: track)
                        }
                        .disabled(!isOnline || playerState.currentTrack == nil || playerState.currentTrack?.isLocalFile == true)
                        Divider()
                    }
                    Button {
                        Task { await triggerSmartShuffle() }
                    } label: {
                        Label("Smart Shuffle", systemImage: "shuffle.circle")
                    }
                    .disabled(container?.serverState.activeServer == nil)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(contentColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .menuOrder(.fixed)
                .buttonStyle(.plain)
                .tint(.primary)
                .accessibilityLabel("More options")
            }
        }
        .sheet(isPresented: $showAlbumSheet) {
            if let track = playerState.currentTrack,
               let albumId = track.albumId,
               let albumName = track.albumName {
                NavigationStack {
                    AlbumDetailView(albumId: albumId, albumName: albumName, coverArtId: track.coverArtId)
                }
            }
        }
        .sheet(item: $preparedShare) { share in
            shareSheet(for: share)
        }
        .sheet(item: $trackInformation) { track in
            TrackInformationSheet(track: track)
        }
        .task(id: shareRequest?.id) {
            await prepareRequestedShare()
        }
    }

    @ViewBuilder
    private var trackMetadata: some View {
        if !compact,
           !playerState.isLiveStream,
           playerState.isPlaybackAvailable,
           let trackSwipe {
            SwipeableTrackMetadata(
                playerState: playerState,
                playerService: container?.playerService,
                interaction: trackSwipe
            ) { song, isCurrent in
                metadata(for: song, isCurrent: isCurrent)
            }
        } else {
            metadata(for: playerState.currentTrack, isCurrent: true)
        }
    }

    private func metadata(for song: DisplayableSong?, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: MinidiscSpacing.xs) {
            metadataTitle(
                playerState.isLiveStream ? (playerState.currentRadio?.name ?? "") : (song?.title ?? ""),
                usesMarquee: isCurrent && !compact && !playerState.isLiveStream
            )

            if isCurrent, let status = playerState.playbackStatusMessage {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(secondaryContentColor)
                    .lineLimit(2)
            } else if playerState.isLiveStream {
                Text("Live Radio")
                    .font(.subheadline)
                    .foregroundStyle(secondaryContentColor)
                    .lineLimit(1)
            } else {
                metadataSubtitle(for: song, isCurrent: isCurrent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func metadataTitle(_ title: String, usesMarquee: Bool) -> some View {
        if usesMarquee {
            MarqueeTrackMetadataText(
                text: title,
                font: .title2,
                weight: .bold,
                color: contentColor
            )
        } else {
            Text(title)
                .font(compact ? .minidiscSectionTitle : .title2)
                .fontWeight(compact ? .semibold : .bold)
                .foregroundStyle(contentColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private func metadataSubtitle(for song: DisplayableSong?, isCurrent: Bool) -> some View {
        if let artist = song?.artist {
            if isCurrent {
                Menu {
                    Button {
                        goToAlbum()
                    } label: {
                        Label("Go to Album", systemImage: "square.stack")
                        if let albumName = song?.albumName ?? playerState.currentTrack?.albumName, !albumName.isEmpty {
                            Text(albumName)
                        }
                    }
                    .disabled((song?.albumName ?? playerState.currentTrack?.albumName) == nil)

                    Button {
                        goToArtist()
                    } label: {
                        Label("Go to Artist", systemImage: "mic")
                        Text(artist)
                    }
                } label: {
                    artistLabel(artist, usesMarquee: !compact)
                }
                .menuOrder(.fixed)
                .buttonStyle(.plain)
                .tint(.primary)
                .disabled(!isOnline && song?.isLocalFile != true)
            } else {
                artistLabel(artist, usesMarquee: false)
            }
        }
    }

    @ViewBuilder
    private func artistLabel(_ artist: String, usesMarquee: Bool) -> some View {
        if usesMarquee {
            MarqueeTrackMetadataText(
                text: artist,
                font: .title3,
                weight: .regular,
                color: secondaryContentColor
            )
        } else {
            Text(artist)
                .font(compact ? .subheadline : .title3)
                .foregroundStyle(secondaryContentColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func prepareRequestedShare() async {
        guard let track = shareRequest else { return }
        let share = await container?.trackSharingService.prepareShare(
            for: track,
            serverIsReachable: isOnline
        )
        guard !Task.isCancelled, shareRequest?.id == track.id else { return }
        shareRequest = nil
        preparedShare = share
    }

    @ViewBuilder
    private func shareSheet(for share: PreparedTrackShare) -> some View {
        switch share {
        case .publicLink(let url):
            SystemShareSheet(item: url)
        case .metadata(let text):
            SystemShareSheet(item: text)
        }
    }

    private func toggleFavorite() {
        guard let songId = playerState.currentTrack?.id, !songId.isEmpty else { return }
        HapticFeedback.light.trigger()
        let wasFavorite = isFavorite
        Task {
            if wasFavorite {
                await container?.toastService.perform { try await container?.favoritesService.unstar(itemType: .song, itemId: songId) }
            } else {
                await container?.toastService.perform { try await container?.favoritesService.star(itemType: .song, itemId: songId) }
            }
        }
    }

    private func goToArtist() {
        guard let track = playerState.currentTrack else { return }
        if track.artistId != nil {
            postNavigateToArtist(track: track)
            return
        }
        guard let name = track.artist else { return }
        Task {
            guard let c = container,
                  let result = try? await c.libraryService.search(name),
                  let found = result.artist?.first else { return }
            postNavigateToArtist(artistId: found.id, artistName: found.name, coverArtId: found.coverArt)
        }
    }

    private func goToAlbum() {
        guard let track = playerState.currentTrack else { return }
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

    private func triggerSmartShuffle() async {
        guard let container else { return }
        do {
            try await container.playerService.playSmartShuffle()
        } catch {
            container.toastService.showError(smartShuffleErrorMessage(from: error))
        }
    }

    private func smartShuffleErrorMessage(from error: Error) -> String {
        if case MinidiscError.smartShuffleEmpty = error {
            return String(localized: "Smart Shuffle unavailable — try playing some tracks first or download more music for offline use.")
        }
        return String(localized: "Smart Shuffle failed. Please try again.")
    }
}

// MARK: - Scrubber

private struct ScrubberView: View {
    let playerState: PlayerState
    let playerService: (any PlayerServiceProtocol)?
    let contentColor: Color
    let secondaryContentColor: Color
    var isLossless: Bool = false
    var isAtmos: Bool = false

    @State private var isDragging = false
    @State private var isSeeking = false
    @State private var displayPosition: TimeInterval = 0

    private var effectiveDuration: TimeInterval {
        playerState.duration > 0 ? playerState.duration : (playerState.currentTrack?.duration ?? 0)
    }

    // Keep the requested position visible until AVPlayer confirms the seek.
    private var positionBinding: Binding<TimeInterval> {
        Binding(
            get: { (isDragging || isSeeking) ? displayPosition : playerState.position },
            set: { newValue in displayPosition = newValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressSlider(
                value: positionBinding,
                total: effectiveDuration,
                onEditingChanged: { editing in
                    isDragging = editing
                    if !editing {
                        isSeeking = true
                        let target = displayPosition
                        Task {
                            defer { isSeeking = false }
                            await playerService?.seek(to: target)
                        }
                    }
                },
                trackColor: contentColor.opacity(0.2),
                fillColor: contentColor.opacity(0.95),
                height: 22,
                isInteracting: isDragging || isSeeking
            )

            ScrubberTimeLabels(
                playerState: playerState,
                effectiveDuration: effectiveDuration,
                overridePosition: (isDragging || isSeeking) ? displayPosition : nil,
                color: secondaryContentColor,
                isLossless: isLossless,
                isAtmos: isAtmos
            )
            .padding(.top, -2)
        }
        .padding(.bottom, 12)
    }
}

/// Isolates periodic position updates from the slider's drag state.
private struct ScrubberTimeLabels: View {
    let playerState: PlayerState
    let effectiveDuration: TimeInterval
    let overridePosition: TimeInterval?
    let color: Color
    var isLossless: Bool = false
    var isAtmos: Bool = false

    var body: some View {
        let shown = overridePosition ?? playerState.position
        HStack {
            Text(Duration.seconds(shown).formatted(.time(pattern: .minuteSecond)))
                .font(.minidiscCaption)
                .foregroundStyle(color)
                .monospacedDigit()
            Spacer()
            HStack(spacing: 8) {
                if isLossless {
                    AudioQualityBadge(.lossless, withBackground: true)
                }
                if isAtmos {
                    AudioQualityBadge(.dolbyAtmos, withBackground: false, textWeight: .regular)
                        .foregroundStyle(color)
                }
            }
            Spacer()
            Text(
                verbatim: "-\(Duration.seconds(max(effectiveDuration - shown, 0)).formatted(.time(pattern: .minuteSecond)))"
            )
                .font(.minidiscCaption)
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}

struct ProgressSlider: View {
    @Binding var value: TimeInterval
    let total: TimeInterval
    let onEditingChanged: (Bool) -> Void
    var trackColor: Color = Color.white.opacity(0.2)
    var fillColor: Color = Color.white.opacity(0.95)
    var height: CGFloat = 32
    var trackHeight: CGFloat = 8
    var isInteracting: Bool = false

    @State private var isDragging = false
    @State private var dragValue: TimeInterval?

    var body: some View {
        GeometryReader { geo in
            let trackW = geo.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)

                Capsule()
                    .fill(fillColor)
                    .frame(width: progressWidth(in: trackW))
                    .animation(nil, value: value)
            }
            .frame(height: isDragging ? 14 : trackHeight)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        // Avoid propagating NaN before the track has a measured width.
                        guard trackW > 0, total > 0, total.isFinite else { return }
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                            HapticFeedback.light.trigger()
                        }
                        let ratio = gesture.location.x / trackW
                        let clampedRatio = max(0, min(1, ratio))
                        dragValue = total * clampedRatio
                        value = dragValue ?? value
                    }
                    .onEnded { _ in
                        guard total > 0, total.isFinite else { return }
                        isDragging = false
                        dragValue = nil
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: height)
        .accessibilityLabel("Playback position")
        .accessibilityValue(Duration.seconds(value).formatted(.time(pattern: .minuteSecond)))
        .accessibilityAdjustableAction { direction in
            let step = total * 0.05
            switch direction {
            case .increment:
                value = min(value + step, total)
                onEditingChanged(false)
            case .decrement:
                value = max(value - step, 0)
                onEditingChanged(false)
            @unknown default: break
            }
        }
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        let displayedValue = dragValue ?? value
        return min(totalWidth, max(0, (CGFloat(displayedValue) / CGFloat(total)) * totalWidth))
    }
}

// MARK: - Playback controls

private struct PlaybackControlsView: View {
    @Environment(\.appContainer) private var container
    let playerState: PlayerState
    let playerService: (any PlayerServiceProtocol)?
    var isPlaybackAvailable: Bool = true
    var keepsPauseIcon: Bool = false
    let contentColor: Color

    var body: some View {
        let showsPause = keepsPauseIcon || playerState.wantsPlayback

        HStack(spacing: MinidiscSpacing.xxxxl) {
            if !playerState.isLiveStream {
                Button {
                    HapticFeedback.light.trigger()
                    Task { await container?.toastService.perform { try await playerService?.skipToPrevious() } }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title)
                        .foregroundStyle(contentColor)
                        .frame(width: 56, height: 56)
                }
                .disabled(playerState.queue.isEmpty)
                .accessibilityLabel("Skip to previous")
            }

            Button {
                HapticFeedback.medium.trigger()
                Task {
                    await playerService?.togglePlayPause()
                }
            } label: {
                Image(systemName: showsPause ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(isPlaybackAvailable ? contentColor : contentColor.opacity(0.4))
                    .frame(width: 80, height: 80)
            }
            .disabled(!isPlaybackAvailable)
            .accessibilityLabel(showsPause ? "Pause" : "Play")
            .accessibilityValue(playerState.playbackStatusMessage ?? "")

            if !playerState.isLiveStream {
                Button {
                    HapticFeedback.light.trigger()
                    Task { await container?.toastService.perform { try await playerService?.skipToNext() } }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title)
                        .foregroundStyle(contentColor)
                        .frame(width: 56, height: 56)
                }
                .disabled(playerState.queue.isEmpty)
                .accessibilityLabel("Skip to next")
            }
        }
    }
}

// MARK: - Bottom toolbar

private struct BottomToolbar: View {
    @Binding var userWantsLyrics: Bool
    let isLyricsShowing: Bool
    let hasLyrics: Bool
    @Binding var surface: PlayerSurface
    let isLiveStream: Bool
    let secondaryContentColor: Color
    let accentColor: Color
    let playerState: PlayerState

    var body: some View {
        HStack(spacing: MinidiscSpacing.xxxxl) {
            if !isLiveStream {
                Button {
                    if surface == .queue {
                        surface = .player
                        userWantsLyrics = true
                    } else {
                        withAnimation(.smooth(duration: 0.3)) { userWantsLyrics.toggle() }
                    }
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.title3)
                        .foregroundStyle(
                            isLyricsShowing && surface == .player
                                ? accentColor
                                : (hasLyrics ? secondaryContentColor : secondaryContentColor.opacity(0.35))
                        )
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Lyrics")
                .disabled(!hasLyrics || playerState.currentTrack?.isLocalFile == true)
            }

            AirPlayRouteButton(tintColor: secondaryContentColor)
                .frame(width: 44, height: 44)

            if !isLiveStream {
                Button {
                    if surface == .queue {
                        surface = .player
                    } else {
                        surface = .queue
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .foregroundStyle(surface == .queue ? accentColor : secondaryContentColor)
                        .overlay(alignment: .topTrailing) {
                            if let badge = playerState.queueModeBadge {
                                Image(systemName: badge)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.minidiscAccent)
                                    .padding(2)
                                    .background(.background, in: Circle())
                                    .overlay(Circle().stroke(.background.opacity(0.5), lineWidth: 0.5))
                                    .offset(x: 6, y: -6)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .animation(.smooth(duration: 0.2), value: playerState.queueModeBadge)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Queue")
            }
        }
    }
}

private struct AirPlayRouteButton: UIViewRepresentable {
    var tintColor: Color = Color.white.opacity(0.7)

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.activeTintColor = UIColor(Color.minidiscAccent)
        view.tintColor = UIColor(tintColor)
        view.backgroundColor = .clear
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = UIColor(tintColor)
    }
}

// MARK: - Volume

private struct VolumeSection: View {
    let contentColor: Color
    let secondaryContentColor: Color

    var body: some View {
        HStack(spacing: MinidiscSpacing.m) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(secondaryContentColor)
                .frame(width: 20)
                .accessibilityHidden(true)

            SystemVolumeView(contentColor: contentColor)

            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(secondaryContentColor)
                .frame(width: 20)
                .accessibilityHidden(true)
        }
    }
}

