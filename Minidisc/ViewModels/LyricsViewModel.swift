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
    private(set) var activeLineIndices: Set<Int> = []
    private(set) var availableLanguages: [String] = []
    var selectedLanguage: String?
    var autoScrollEnabled: Bool = true
    private(set) var isUserScrolling: Bool = false

    private var lastPositionUpdateTime: Date = Date()
    private var lastRecordedPosition: Double = 0

    var currentPosition: Double {
        interpolatedPosition()
    }

    func interpolatedPosition(at date: Date = Date()) -> Double {
        guard isPlaying else { return playerState.position }
        if abs(playerState.position - lastRecordedPosition) > 0.05 {
            lastRecordedPosition = playerState.position
            lastPositionUpdateTime = Date()
        }
        let delta = date.timeIntervalSince(lastPositionUpdateTime)
        if delta < 0 || delta > 3.0 {
            return playerState.position
        }
        return playerState.position + delta
    }

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
            album: track.albumName,
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

    private func getLineEndTime(line: NowLocalLyricLine, index: Int, lines: [NowLocalLyricLine]) -> Double {
        let nextStart = (index + 1 < lines.count) ? lines[index + 1].time : Double.infinity
        var maxWordEnd: Double = 0

        if line.hasAdlib == true {
            let mW = line.main?.words
            let aW = line.adlib?.words
            let mEnd = mW?.last?.endTime ?? ((mW?.last?.time).map { $0 + 0.8 } ?? 0)
            let aEnd = aW?.last?.endTime ?? ((aW?.last?.time).map { $0 + 0.8 } ?? 0)
            maxWordEnd = max(mEnd, aEnd)
        } else if let last = line.words?.last {
            maxWordEnd = last.endTime ?? (last.time + 0.8)
        }

        var sungEnd: Double = 0
        if let e = line.endTime, e > line.time {
            sungEnd = e
        }
        if maxWordEnd > sungEnd {
            sungEnd = maxWordEnd
        }

        if sungEnd > line.time {
            if index + 1 < lines.count {
                return (sungEnd <= nextStart) ? nextStart : sungEnd
            }
            return sungEnd
        }

        let fallbackDuration = (index + 1 < lines.count) ? 2.0 : 3.5
        return min(line.time + fallbackDuration, nextStart)
    }

    func update(elapsedMs: Int) {
        if case .loadedTTML(let ttml) = state {
            let currentSec = Double(elapsedMs) / 1000.0
            var newIndices = Set<Int>()

            for (index, line) in ttml.lyrics.enumerated() {
                if line.time <= currentSec {
                    let lEnd = getLineEndTime(line: line, index: index, lines: ttml.lyrics)
                    if currentSec < lEnd {
                        newIndices.insert(index)
                    }
                } else {
                    break
                }
            }

            if newIndices.isEmpty {
                var lastStarted = 0
                for (index, line) in ttml.lyrics.enumerated() {
                    if line.time <= currentSec {
                        lastStarted = index
                    } else {
                        break
                    }
                }
                newIndices.insert(lastStarted)
            }

            if newIndices != activeLineIndices {
                activeLineIndices = newIndices
                currentLineIndex = newIndices.min()
            }
            return
        }

        guard case .loaded(let structured) = state, structured.synced else {
            currentLineIndex = nil
            activeLineIndices = []
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
            activeLineIndices = newIndex.map { Set([$0]) } ?? []
        }
    }

    // MARK: - Seek

    func userTapped(seconds: Double) {
        resumeTask?.cancel()
        isUserScrolling = false
        lastRecordedPosition = seconds
        lastPositionUpdateTime = Date()
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
        lastRecordedPosition = playerState.position
        lastPositionUpdateTime = Date()
        trackingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
                guard let self else { return }
                self.update(elapsedMs: Int(self.interpolatedPosition() * 1000))
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
