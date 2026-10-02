import SwiftUI

// MARK: - Dot Physics for Instrumental Pauses (Replicating movil.html)

struct DotPhysicsResult {
    let rowScale: CGFloat
    let rowOpacity: Double
    let a1: Double
    let a2: Double
    let a3: Double
}

func computeDotPhysics(currentTimeSec: Double, startTime: Double, nextTime: Double) -> DotPhysicsResult {
    let dur = max(0.8, nextTime - startTime)
    let elapsed = currentTimeSec - startTime
    let ratio = max(0.0, min(1.0, elapsed / dur))
    let timeRemaining = max(0.0, nextTime - currentTimeSec)

    let finalDuration = min(2.0, max(0.8, dur * 0.35))
    let isFinalPulse = timeRemaining <= finalDuration

    let fillEndRatio = max(0.5, 1.0 - (finalDuration / dur))
    let p1End = fillEndRatio * 0.33
    let p2End = fillEndRatio * 0.66
    let p3End = fillEndRatio

    var a1: Double = 0.28
    var a2: Double = 0.28
    var a3: Double = 0.28

    if ratio <= p1End {
        a1 = 0.28 + 0.72 * max(0.0, min(1.0, ratio / p1End))
    } else {
        a1 = 1.0
    }

    if ratio > p1End && ratio <= p2End {
        a2 = 0.28 + 0.72 * max(0.0, min(1.0, (ratio - p1End) / (p2End - p1End)))
    } else if ratio > p2End {
        a2 = 1.0
    }

    if ratio > p2End && ratio <= p3End {
        a3 = 0.28 + 0.72 * max(0.0, min(1.0, (ratio - p2End) / (p3End - p2End)))
    } else if ratio > p3End {
        a3 = 1.0
    }

    var rowScale: CGFloat = 1.0
    var rowOpacity: Double = 1.0

    let cutoffElapsed = max(0.0, dur - finalDuration)
    let cutPhase = (cutoffElapsed / 4.0) * .pi * 2.0
    let cutWave = 0.5 - 0.5 * cos(cutPhase)
    let startScaleForFinal = 0.98 + 0.20 * cutWave

    if !isFinalPulse {
        let pulsePeriod = 4.0
        let pulsePhase = (max(0.0, elapsed) / pulsePeriod) * .pi * 2.0
        let pulseWave = 0.5 - 0.5 * cos(pulsePhase)
        rowScale = CGFloat(0.98 + 0.20 * pulseWave)
    } else {
        let progressFinal = 1.0 - (timeRemaining / finalDuration)
        if progressFinal < 0.50 {
            let tA = progressFinal / 0.50
            rowScale = CGFloat(startScaleForFinal + (1.34 - startScaleForFinal) * sin(tA * .pi / 2.0))
            rowOpacity = 1.0
            a1 = 1.0; a2 = 1.0; a3 = 1.0
        } else {
            let tB = (progressFinal - 0.50) / 0.50
            let shrinkDuration = 0.52
            if tB < shrinkDuration {
                let p = tB / shrinkDuration
                rowScale = CGFloat(max(0.0, 1.34 * (1.0 - pow(p, 1.2))))
                rowOpacity = max(0.0, 1.0 - pow(p, 1.3))
            } else {
                rowScale = 0.0
                rowOpacity = 0.0
            }
            a1 = rowOpacity; a2 = rowOpacity; a3 = rowOpacity
        }
    }

    return DotPhysicsResult(rowScale: rowScale, rowOpacity: rowOpacity, a1: a1, a2: a2, a3: a3)
}

// MARK: - Three Dots View (Instrumental Marker)

struct ThreeDotsView: View {
    let currentTime: Double
    let startTime: Double
    let nextTime: Double
    let isAgentV2: Bool

    var body: some View {
        let physics = computeDotPhysics(
            currentTimeSec: currentTime,
            startTime: startTime,
            nextTime: nextTime
        )

        HStack(spacing: 8) {
            Circle()
                .fill(Color.white)
                .frame(width: 9, height: 9)
                .opacity(physics.a1)
                .shadow(color: .white.opacity(physics.a1 * 0.45), radius: 3)

            Circle()
                .fill(Color.white)
                .frame(width: 9, height: 9)
                .opacity(physics.a2)
                .shadow(color: .white.opacity(physics.a2 * 0.45), radius: 3)

            Circle()
                .fill(Color.white)
                .frame(width: 9, height: 9)
                .opacity(physics.a3)
                .shadow(color: .white.opacity(physics.a3 * 0.45), radius: 3)
        }
        .frame(height: 42)
        .scaleEffect(physics.rowScale, anchor: isAgentV2 ? .trailing : .leading)
        .opacity(physics.rowOpacity)
        .frame(maxWidth: .infinity, alignment: isAgentV2 ? .trailing : .leading)
    }
}

// MARK: - Wrapping Flow Layout for Karaoke Words

struct LyricsFlowLayout: Layout {
    var horizontalAlignment: HorizontalAlignment = .leading
    var verticalSpacing: CGFloat = 2

    init(horizontalAlignment: HorizontalAlignment = .leading, verticalSpacing: CGFloat = 2) {
        self.horizontalAlignment = horizontalAlignment
        self.verticalSpacing = verticalSpacing
    }

    private struct Row {
        var subviews: [LayoutSubview] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var currentRow = Row()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRow.width + size.width > maxWidth && !currentRow.subviews.isEmpty {
                rows.append(currentRow)
                currentRow = Row()
            }
            currentRow.subviews.append(subview)
            currentRow.sizes.append(size)
            currentRow.width += size.width
            currentRow.height = max(currentRow.height, size.height)
        }
        if !currentRow.subviews.isEmpty {
            rows.append(currentRow)
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let totalHeight = rows.reduce(CGFloat(0)) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * verticalSpacing
        let maxWidth = rows.reduce(CGFloat(0)) { max($0, $1.width) }
        return CGSize(width: proposal.width ?? maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x: CGFloat = bounds.minX
            if horizontalAlignment == .trailing {
                x = bounds.maxX - row.width
            }

            for (subview, size) in zip(row.subviews, row.sizes) {
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width
            }
            y += row.height + verticalSpacing
        }
    }
}

// MARK: - Word Unit Grouping (Prevents breaking words across lines)

private func groupWordsIntoWordUnits(_ words: [NowLocalLyricWord]) -> [[NowLocalLyricWord]] {
    var groups: [[NowLocalLyricWord]] = []
    var currentGroup: [NowLocalLyricWord] = []

    for w in words {
        currentGroup.append(w)

        let trimmed = w.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasWhitespace = w.text.contains(where: { $0.isWhitespace || $0.isNewline })

        // Chinese / Japanese ideographs and kana naturally wrap per character
        let isCJKNoSpace = !trimmed.isEmpty && trimmed.unicodeScalars.allSatisfy { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || // CJK Unified Ideographs
            (0x3040...0x309F).contains(scalar.value) || // Hiragana
            (0x30A0...0x30FF).contains(scalar.value)    // Katakana
        }

        if hasWhitespace || isCJKNoSpace {
            groups.append(currentGroup)
            currentGroup = []
        }
    }
    if !currentGroup.isEmpty {
        groups.append(currentGroup)
    }
    return groups
}

struct TTMLWordUnitView: View {
    let words: [NowLocalLyricWord]
    let currentTime: Double
    let isLineActive: Bool
    var font: Font = .system(size: 34, weight: .bold)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, w in
                TTMLWordSpanView(
                    word: w,
                    currentTime: currentTime,
                    isLineActive: isLineActive,
                    font: font
                )
            }
        }
    }
}

// MARK: - Karaoke Configuration Helper

private func karaokeConfig(isLineActive: Bool, dimOpacity: Double = 0.45, litColor: Color = .white) -> KaraokeConfiguration {
    var config = KaraokeConfiguration.standard
    config.feather = 6.0
    config.glowStrength = 0.0
    config.bounceHeight = 0.0
    config.bounceScale = 0.0
    if !isLineActive {
        // Same color as letters before they are filled (0.45 opacity)
        config.dimColor = Color.white.opacity(dimOpacity)
        config.litColor = Color.white.opacity(dimOpacity)
    } else {
        config.dimColor = Color.white.opacity(dimOpacity)
        config.litColor = litColor
    }
    return config
}

// MARK: - Word Span View (Karaoke Lighting & Elevation)

struct TTMLWordSpanView: View {
    let word: NowLocalLyricWord
    let currentTime: Double
    let isLineActive: Bool
    var font: Font = .system(size: 34, weight: .bold)

    var body: some View {
        let start = word.time
        let end = word.endTime ?? (word.time + 0.35)

        Text(word.text)
            .font(font)
            .karaoke(
                time: currentTime,
                start: start,
                end: end,
                configuration: karaokeConfig(isLineActive: isLineActive)
            )
    }
}

// MARK: - TTMLLineContentView (Main vocals & optional adlibs)

struct TTMLLineContentView: View {
    let line: NowLocalLyricLine
    let currentTime: Double
    let isLineActive: Bool
    let isV2: Bool
    let hasWordSync: Bool
    let isUserScrolling: Bool
    var nextLineTime: Double? = nil

    private var alignment: HorizontalAlignment {
        isV2 ? .trailing : .leading
    }

    private var isAdlibBefore: Bool {
        line.adlibIsBefore ?? (line.adlib != nil && (line.adlib?.time ?? .infinity) < (line.main?.time ?? line.time))
    }

    @ViewBuilder
    private var mainVocalsView: some View {
        if let mainWords = line.main?.words, !mainWords.isEmpty, hasWordSync {
            LyricsFlowLayout(horizontalAlignment: alignment, verticalSpacing: 2) {
                ForEach(Array(groupWordsIntoWordUnits(mainWords).enumerated()), id: \.offset) { _, group in
                    TTMLWordUnitView(
                        words: group,
                        currentTime: currentTime,
                        isLineActive: isLineActive,
                        font: .system(size: 34, weight: .bold)
                    )
                }
            }
        } else if let words = line.words, !words.isEmpty, hasWordSync {
            LyricsFlowLayout(horizontalAlignment: alignment, verticalSpacing: 2) {
                ForEach(Array(groupWordsIntoWordUnits(words).enumerated()), id: \.offset) { _, group in
                    TTMLWordUnitView(
                        words: group,
                        currentTime: currentTime,
                        isLineActive: isLineActive,
                        font: .system(size: 34, weight: .bold)
                    )
                }
            }
        } else {
            let start = line.main?.time ?? line.time
            let end = line.main?.endTime ?? line.endTime ?? nextLineTime.map { min($0, start + 6.0) } ?? (start + 3.0)

            Text(line.main?.text ?? line.text)
                .font(.system(size: 34, weight: .bold))
                .karaoke(
                    time: currentTime,
                    start: start,
                    end: end,
                    configuration: karaokeConfig(isLineActive: isLineActive)
                )
                .multilineTextAlignment(isV2 ? .trailing : .leading)
        }
    }

    @ViewBuilder
    private var adlibsView: some View {
        if line.hasAdlib == true, let adlib = line.adlib, isLineActive && !isUserScrolling {
            if let adlibWords = adlib.words, !adlibWords.isEmpty, hasWordSync {
                LyricsFlowLayout(horizontalAlignment: alignment, verticalSpacing: 2) {
                    ForEach(Array(groupWordsIntoWordUnits(adlibWords).enumerated()), id: \.offset) { _, group in
                        TTMLWordUnitView(
                            words: group,
                            currentTime: currentTime,
                            isLineActive: isLineActive,
                            font: .system(size: 20, weight: .bold)
                        )
                    }
                }
                .opacity(0.85)
                .transition(.opacity.combined(with: .offset(y: isAdlibBefore ? -4 : 4)))
            } else if let adlibText = adlib.text, !adlibText.isEmpty {
                let aStart = adlib.time ?? line.time
                let aEnd = adlib.endTime ?? line.endTime ?? (aStart + 2.5)

                Text(adlibText)
                    .font(.system(size: 20, weight: .bold))
                    .karaoke(
                        time: currentTime,
                        start: aStart,
                        end: aEnd,
                        configuration: karaokeConfig(
                            isLineActive: isLineActive,
                            dimOpacity: 0.18,
                            litColor: Color.white.opacity(0.85)
                        )
                    )
                    .multilineTextAlignment(isV2 ? .trailing : .leading)
                    .transition(.opacity.combined(with: .offset(y: isAdlibBefore ? -4 : 4)))
            }
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            if isAdlibBefore {
                adlibsView
                mainVocalsView
            } else {
                mainVocalsView
                adlibsView
            }
        }
    }
}

// MARK: - Single Line Container (Spatial layout v1/v2, physics, blur, scale)

struct TTMLLyricsLineView: View {
    let line: NowLocalLyricLine
    let index: Int
    let activeIndices: Set<Int>
    let currentIndex: Int?
    let currentTime: Double
    let nextLineTime: Double?
    let hasMultiArtist: Bool
    let hasWordSync: Bool
    let isUserScrolling: Bool
    let onSeek: () -> Void

    private var isV2: Bool {
        line.agent == "v2"
    }

    private var isDotMarker: Bool {
        line.text == "…" || line.text == "..."
    }

    private var isLineActive: Bool {
        activeIndices.contains(index)
    }

    private var distance: Int {
        if isLineActive { return 0 }
        guard !activeIndices.isEmpty else { return 0 }
        if let minActive = activeIndices.min(), index < minActive {
            return minActive - index
        }
        if let maxActive = activeIndices.max(), index > maxActive {
            return index - maxActive
        }
        return 0
    }

    private var blurRadius: CGFloat {
        if isUserScrolling { return 0 }
        if isLineActive { return 0 }
        guard !activeIndices.isEmpty else { return 0 }
        switch distance {
        case 1: return 2.0
        case 2: return 3.5
        default: return 5.0
        }
    }

    private var opacity: Double {
        1.0
    }

    private var scale: CGFloat {
        1.0
    }

    var body: some View {
        Group {
            if isDotMarker {
                if isLineActive && !isUserScrolling {
                    let nextT = nextLineTime ?? (line.time + 8.0)
                    ThreeDotsView(
                        currentTime: currentTime,
                        startTime: line.time,
                        nextTime: nextT,
                        isAgentV2: isV2
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                } else {
                    Color.clear.frame(height: 0)
                }
            } else {
                TTMLLineContentView(
                    line: line,
                    currentTime: currentTime,
                    isLineActive: isLineActive,
                    isV2: isV2,
                    hasWordSync: hasWordSync,
                    isUserScrolling: isUserScrolling,
                    nextLineTime: nextLineTime
                )
                .frame(maxWidth: .infinity, alignment: isV2 ? .trailing : .leading)
                .padding(.leading, (hasMultiArtist && isV2) ? 24 : 0)
                .padding(.trailing, (hasMultiArtist && !isV2) ? 24 : 0)
                .opacity(opacity)
                .blur(radius: blurRadius)
                .scaleEffect(scale, anchor: isV2 ? .trailing : .leading)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isLineActive)
                .animation(.easeInOut(duration: 0.25), value: isUserScrolling)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSeek()
        }
    }
}

// MARK: - Main TTMLLyricsView

struct TTMLLyricsView: View {
    @Bindable var viewModel: LyricsViewModel
    let lyricsResponse: NowLocalLyricsResponse

    private var hasMultiArtist: Bool {
        lyricsResponse.lyrics.contains { $0.agent == "v2" }
    }

    private var hasWordSync: Bool {
        lyricsResponse.hasWordSync ?? true
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !viewModel.isPlaying)) { timeline in
            let currentTime = viewModel.interpolatedPosition(at: timeline.date)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 22) {
                        ForEach(Array(lyricsResponse.lyrics.enumerated()), id: \.offset) { index, line in
                            let isDot = (line.text == "…" || line.text == "...")
                            let isActive = viewModel.activeLineIndices.contains(index)

                            if !isDot || (isActive && !viewModel.isUserScrolling) {
                                let nextLineTime = (index + 1 < lyricsResponse.lyrics.count) ? lyricsResponse.lyrics[index + 1].time : nil

                                TTMLLyricsLineView(
                                    line: line,
                                    index: index,
                                    activeIndices: viewModel.activeLineIndices,
                                    currentIndex: viewModel.currentLineIndex,
                                    currentTime: currentTime,
                                    nextLineTime: nextLineTime,
                                    hasMultiArtist: hasMultiArtist,
                                    hasWordSync: hasWordSync,
                                    isUserScrolling: viewModel.isUserScrolling,
                                    onSeek: {
                                        viewModel.userTapped(seconds: line.time)
                                    }
                                )
                                .id(index)
                            }
                        }

                        if let composer = lyricsResponse.composer, !composer.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(Text("Compositores: ").foregroundColor(.white.opacity(0.45))) \(Text(composer).foregroundColor(.white.opacity(0.65)).bold())")
                                    .font(.system(size: 14))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 28)
                            .padding(.bottom, 40)
                        }
                    }
                    .padding(.horizontal, MinidiscSpacing.l)
                    .padding(.top, 60)
                    .padding(.bottom, 220)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    if let currentIndex = viewModel.currentLineIndex {
                        let anchor = UnitPoint(x: 0.5, y: 0.118)
                        proxy.scrollTo(currentIndex, anchor: anchor)
                    }
                }
                .onChange(of: viewModel.currentLineIndex) { _, newIndex in
                    guard viewModel.autoScrollEnabled,
                          !viewModel.isUserScrolling,
                          let newIndex else { return }
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                        let anchor = UnitPoint(x: 0.5, y: 0.118)
                        proxy.scrollTo(newIndex, anchor: anchor)
                    }
                }
                .onScrollPhaseChange { _, newPhase in
                    switch newPhase {
                    case .interacting:
                        viewModel.userStartedScrolling()
                    case .decelerating, .idle:
                        guard viewModel.isUserScrolling else { return }
                        viewModel.userStoppedScrolling()
                    default:
                        break
                    }
                }
            }
        }
    }
}
