import SwiftUI
import SwiftSonic

@Observable
@MainActor
final class LyricsViewModel {
    private let lyricsService: LyricsService
    private let playerService: any PlayerServiceProtocol
    private let playerState: PlayerState
    private let track: DisplayableSong
    private let serverId: UUID
    private let source: LyricsSource
    private let activeServerBaseURL: String?

    private(set) var state: State = .loading
    private(set) var currentLineIndex: Int?
    private(set) var availableLanguages: [String] = []
    var selectedLanguage: String?
    var autoScrollEnabled: Bool = true
    private(set) var isUserScrolling: Bool = false

    var currentPosition: Double { playerState.position }

    private var lyricsList: LyricsList?
    private var trackingTask: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    private var isShown = false

    nonisolated enum State: Equatable {
        case loading
        case loaded(StructuredLyrics)
        case loadedTTML(NowLocalLyricsResponse)
        case empty
        case unsupported
        case error(String)
    }

    init(
        track: DisplayableSong,
        serverId: UUID,
        source: LyricsSource,
        lyricsService: LyricsService,
        playerService: any PlayerServiceProtocol,
        playerState: PlayerState,
        activeServerBaseURL: String? = nil
    ) {
        self.track = track
        self.serverId = serverId
        self.source = source
        self.lyricsService = lyricsService
        self.playerService = playerService
        self.playerState = playerState
        self.activeServerBaseURL = activeServerBaseURL
    }

    isolated deinit {
        trackingTask?.cancel()
        resumeTask?.cancel()
    }

    // MARK: - Load

    func load() async {
        state = .loading

        // 1. Try TTML / rich lyrics from NowLocal backend first
        if let enrichment = await NowLocalService.shared.fetchEnrichment(
            album: track.album,
            artist: track.artist,
            title: track.title,
            activeServerBaseURL: activeServerBaseURL
        ), let lyricsUrl = enrichment.lyricsUrl {
            if let nowLocalLyrics = await NowLocalService.shared.fetchLyrics(
                pathOrTrackId: lyricsUrl,
                activeServerBaseURL: activeServerBaseURL
            ), !nowLocalLyrics.lyrics.isEmpty {
                state = .loadedTTML(nowLocalLyrics)
                currentLineIndex = nil
                reconcileTracking()
                return
            }
        }

        // 2. Fall back to standard server/LRCLIB lyrics
        do {
            let list = try await lyricsService.fetchLyrics(
                for: track,
                serverId: serverId,
                source: source
            )
            lyricsList = list
            applyCurrentLanguage()
        } catch LyricsError.notSupportedByServer {
            state = .unsupported
        } catch LyricsError.notFound {
            state = .empty
        } catch let error as LyricsError {
            state = .error(networkErrorMessage(from: error))
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Line tracking

    func update(elapsedMs: Int) {
        if case .loadedTTML(let ttml) = state {
            let currentSec = Double(elapsedMs) / 1000.0
            var newIndex: Int? = nil
            for (index, line) in ttml.lyrics.enumerated() {
                let nextTime = (index + 1 < ttml.lyrics.count) ? ttml.lyrics[index + 1].time : (line.endTime ?? (line.time + 4.0))
                if currentSec >= line.time && currentSec < nextTime {
                    newIndex = index
                    break
                }
            }
            if newIndex != currentLineIndex {
                currentLineIndex = newIndex
            }
            return
        }

        guard case .loaded(let structured) = state, structured.synced else {
            currentLineIndex = nil
            return
        }
        let adjustedMs = elapsedMs - structured.offset
        var newIndex: Int? = nil
        for (index, line) in structured.line.enumerated() {
            guard let start = line.start else { continue }
            if start <= adjustedMs {
                newIndex = index
            } else {
                break
            }
        }
        if newIndex != currentLineIndex {
            currentLineIndex = newIndex
        }
    }

    // MARK: - Seek

    func userTapped(seconds: Double) {
        Task { [weak self] in
            await self?.playerService.seek(to: seconds)
        }
    }

    func userTapped(lineIndex: Int) {
        if case .loadedTTML(let ttml) = state {
            guard lineIndex < ttml.lyrics.count else { return }
            let targetSeconds = ttml.lyrics[lineIndex].time
            userTapped(seconds: targetSeconds)
            return
        }

        guard case .loaded(let structured) = state, structured.synced else { return }
        guard lineIndex < structured.line.count else { return }
        guard let startMs = structured.line[lineIndex].start else { return }
        let targetSeconds = TimeInterval(startMs + structured.offset) / 1000.0
        userTapped(seconds: targetSeconds)
    }

    // MARK: - Auto-scroll

    func userStartedScrolling() {
        isUserScrolling = true
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.isUserScrolling = false
        }
    }

    func userStoppedScrolling() {
        userStartedScrolling()
    }

    // MARK: - Language selection

    func selectLanguage(_ lang: String) {
        guard selectedLanguage != lang else { return }
        selectedLanguage = lang
        currentLineIndex = nil
        applyCurrentLanguage()
    }

    // MARK: - Timer lifecycle

    var isPlaying: Bool { playerState.playbackState == .playing }

    private var hasSyncedLyrics: Bool {
        switch state {
        case .loadedTTML:
            return true
        case .loaded(let structured):
            return structured.synced
        default:
            return false
        }
    }

    /// Called when the lyrics view appears/disappears. The auto-scroll resume task is torn down on hide.
    func setVisible(_ visible: Bool) {
        isShown = visible
        if !visible {
            resumeTask?.cancel()
            resumeTask = nil
        }
        reconcileTracking()
    }

    /// Runs line tracking only for visible, playing, time-synced lyrics.
    func reconcileTracking() {
        if isShown && isPlaying && hasSyncedLyrics {
            startTimer()
        } else {
            stopTimer()
        }
    }

    private func startTimer() {
        guard trackingTask == nil else { return }
        trackingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
                guard let self else { return }
                self.update(elapsedMs: Int(self.playerState.position * 1000))
            }
        }
    }

    private func stopTimer() {
        trackingTask?.cancel()
        trackingTask = nil
    }

    // MARK: - Private helpers

    private func applyCurrentLanguage() {
        guard let list = lyricsList else { return }
        var seen = Set<String>()
        availableLanguages = list.structuredLyrics
            .compactMap { $0.lang }
            .filter { seen.insert($0).inserted }
        let best = lyricsService.selectBestLanguage(from: list, preferred: selectedLanguage)
        currentLineIndex = nil
        state = best.map { .loaded($0) } ?? .empty
        reconcileTracking()
    }

    private func networkErrorMessage(from error: LyricsError) -> String {
        if case .networkError(let msg) = error { return msg }
        return error.localizedDescription
    }
}
