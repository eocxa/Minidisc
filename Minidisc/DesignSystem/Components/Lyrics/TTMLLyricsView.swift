import SwiftUI

// MARK: - Dot Physics for Instrumental Pauses (Replicating index.html / Apple Music countdown)

struct DotPhysicsResult {
    let rowScale: CGFloat
    let rowOpacity: Double
    let a1: Double
    let a2: Double
    let a3: Double
    let scale1: CGFloat
    let scale2: CGFloat
    let scale3: CGFloat
}

func computeDotPhysics(currentTimeSec: Double, startTime: Double, nextTime: Double) -> DotPhysicsResult {
    let dur = max(0.8, nextTime - startTime)
    let timeRemaining = max(0.0, nextTime - currentTimeSec)

    var a1: Double = 0.25, a2: Double = 0.25, a3: Double = 0.25
    var scale1: CGFloat = 1.0, scale2: CGFloat = 1.0, scale3: CGFloat = 1.0
    var rowScale: CGFloat = 1.0
    var rowOpacity: Double = 1.0

    let countdownDur = min(3.0, max(0.8, dur * 0.75))
    let t3 = countdownDur
    let t2 = countdownDur * (2.0 / 3.0)
    let t1 = countdownDur * (1.0 / 3.0)

    if timeRemaining > t3 {
        // Idle phase: subtle rhythmic breathing
        let idlePhase = (currentTimeSec - startTime) * 2.4
        rowScale = CGFloat(0.96 + 0.05 * sin(idlePhase))
        rowOpacity = 0.85
    } else if timeRemaining > t2 {
        // Dot 1 turns on with bounce
        let p1 = max(0.0, min(1.0, (t3 - timeRemaining) / max(0.1, t3 - t2)))
        a1 = 1.0
        scale1 = CGFloat(p1 < 0.35 ? 1.0 + 0.38 * sin((p1 / 0.35) * .pi) : 1.0)
        rowScale = 1.02
        rowOpacity = 1.0
    } else if timeRemaining > t1 {
        // Dot 2 turns on with bounce
        let p2 = max(0.0, min(1.0, (t2 - timeRemaining) / max(0.1, t2 - t1)))
        a1 = 1.0
        a2 = 1.0
        scale1 = 1.0
        scale2 = CGFloat(p2 < 0.35 ? 1.0 + 0.38 * sin((p2 / 0.35) * .pi) : 1.0)
        rowScale = 1.04
        rowOpacity = 1.0
    } else if timeRemaining > 0.32 {
        // Dot 3 turns on with bounce - all 3 lit
        let p3 = max(0.0, min(1.0, (t1 - timeRemaining) / max(0.1, t1 - 0.32)))
        a1 = 1.0
        a2 = 1.0
        a3 = 1.0
        scale1 = 1.0
        scale2 = 1.0
        scale3 = CGFloat(p3 < 0.35 ? 1.0 + 0.38 * sin((p3 / 0.35) * .pi) : 1.0)
        rowScale = 1.08
        rowOpacity = 1.0
    } else {
        // Final fade out and contraction before singing starts (last 0.32s)
        let pEnd = max(0.0, timeRemaining / 0.32)
        rowScale = CGFloat(max(0.0, pEnd * 1.08))
        rowOpacity = max(0.0, pow(pEnd, 1.4))
        a1 = rowOpacity
        a2 = rowOpacity
        a3 = rowOpacity
    }

    return DotPhysicsResult(
        rowScale: rowScale,
        rowOpacity: rowOpacity,
        a1: a1,
        a2: a2,
        a3: a3,
        scale1: scale1,
        scale2: scale2,
        scale3: scale3
    )
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
                .scaleEffect(physics.scale1)
                .shadow(color: .white.opacity(physics.a1 * 0.45), radius: 3)

            Circle()
                .fill(Color.white)
                .frame(width: 9, height: 9)
                .opacity(physics.a2)
                .scaleEffect(physics.scale2)
                .shadow(color: .white.opacity(physics.a2 * 0.45), radius: 3)

            Circle()
                .fill(Color.white)
                .frame(width: 9, height: 9)
                .opacity(physics.a3)
                .scaleEffect(physics.scale3)
                .shadow(color: .white.opacity(physics.a3 * 0.45), radius: 3)
        }
        .frame(height: 24)
        .scaleEffect(physics.rowScale, anchor: isAgentV2 ? .trailing : .leading)
        .opacity(physics.rowOpacity)
        .frame(maxWidth: .infinity, alignment: isAgentV2 ? .trailing : .leading)
    }
}

// MARK: - Wrapping Flow Layout for Karaoke Words

struct LyricsFlowLayout: Layout {
    var horizontalAlignment: HorizontalAlignment = .leading
    var verticalSpacing: CGFloat = 4

    init(horizontalAlignment: HorizontalAlignment = .leading, verticalSpacing: CGFloat = 4) {
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

// MARK: - Karaoke Configuration Helper

private func karaokeConfig(isLineActive: Bool, dimOpacity: Double = 0.22, litColor: Color = .white) -> KaraokeConfiguration {
    var config = KaraokeConfiguration.standard
    config.litColor = litColor
    if !isLineActive {
        config.dimColor = Color.white.opacity(dimOpacity)
        config.glowStrength = 0.0
        config.bounceHeight = 0.0
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

    private var alignment: HorizontalAlignment {
        isV2 ? .trailing : .leading
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            // Main vocals
            if let mainWords = line.main?.words, !mainWords.isEmpty, hasWordSync {
                LyricsFlowLayout(horizontalAlignment: alignment) {
                    ForEach(mainWords) { w in
                        TTMLWordSpanView(
                            word: w,
                            currentTime: currentTime,
                            isLineActive: isLineActive,
                            font: .system(size: 34, weight: .bold)
                        )
                    }
                }
            } else if let words = line.words, !words.isEmpty, hasWordSync {
                LyricsFlowLayout(horizontalAlignment: alignment) {
                    ForEach(words) { w in
                        TTMLWordSpanView(
                            word: w,
                            currentTime: currentTime,
                            isLineActive: isLineActive,
                            font: .system(size: 34, weight: .bold)
                        )
                    }
                }
            } else {
                let start = line.time
                let end = line.endTime ?? (line.time + 3.5)

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

            // Adlibs vocals (if present) - only emerge when line is active and not user-scrolling
            if line.hasAdlib == true, let adlib = line.adlib, isLineActive && !isUserScrolling {
                Group {
                    if let adlibWords = adlib.words, !adlibWords.isEmpty, hasWordSync {
                        LyricsFlowLayout(horizontalAlignment: alignment) {
                            ForEach(adlibWords) { w in
                                TTMLWordSpanView(
                                    word: w,
                                    currentTime: currentTime,
                                    isLineActive: isLineActive,
                                    font: .system(size: 24, weight: .bold)
                                )
                            }
                        }
                    } else if let adlibText = adlib.text, !adlibText.isEmpty {
                        let start = adlib.time ?? line.time
                        let end = adlib.endTime ?? (start + 3.0)

                        Text(adlibText)
                            .font(.system(size: 24, weight: .bold))
                            .karaoke(
                                time: currentTime,
                                start: start,
                                end: end,
                                configuration: karaokeConfig(
                                    isLineActive: isLineActive,
                                    dimOpacity: 0.18,
                                    litColor: Color.white.opacity(0.85)
                                )
                            )
                            .multilineTextAlignment(isV2 ? .trailing : .leading)
                    }
                }
                .opacity(0.85)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 8)).combined(with: .scale(scale: 0.96)),
                    removal: .opacity.combined(with: .offset(y: 6)).combined(with: .scale(scale: 0.96))
                ))
            }
        }
        .animation(.timingCurve(0.2, 0.95, 0.3, 1.0, duration: 0.70), value: isLineActive)
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
        case 1: return 0.8
        case 2: return 2.0
        default: return 4.0
        }
    }

    private var opacity: Double {
        if isUserScrolling {
            return isLineActive ? 1.0 : 0.58
        }
        if isLineActive { return 1.0 }
        guard let minActive = activeIndices.min() else { return 1.0 }
        if index < minActive {
            return distance == 1 ? 0.38 : 0.22
        }
        switch distance {
        case 1: return 0.55
        case 2: return 0.38
        case 3: return 0.28
        default: return 0.18
        }
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
                    isUserScrolling: isUserScrolling
                )
                .frame(maxWidth: .infinity, alignment: isV2 ? .trailing : .leading)
                .padding(.leading, (hasMultiArtist && isV2) ? 44 : 0)
                .padding(.trailing, (hasMultiArtist && !isV2) ? 44 : 0)
                .opacity(opacity)
                .blur(radius: blurRadius)
                .scaleEffect(scale, anchor: isV2 ? .trailing : .leading)
                .animation(.timingCurve(0.2, 0.95, 0.3, 1.0, duration: 0.65), value: isLineActive)
                .animation(.timingCurve(0.2, 0.95, 0.3, 1.0, duration: 0.35), value: isUserScrolling)
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
                    LazyVStack(spacing: 36) {
                        ForEach(Array(lyricsResponse.lyrics.enumerated()), id: \.offset) { index, line in
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
                    .padding(.horizontal, 16)
                    .padding(.top, 36)
                    .padding(.bottom, 220)
                }
                .scrollIndicators(.hidden)
                .onChange(of: viewModel.currentLineIndex) { _, newIndex in
                    guard viewModel.autoScrollEnabled,
                          !viewModel.isUserScrolling,
                          let newIndex else { return }
                    withAnimation(.timingCurve(0.2, 0.95, 0.3, 1.0, duration: 0.68)) {
                        let anchor: UnitPoint = (newIndex == 0) ? .top : UnitPoint(x: 0.5, y: 0.28)
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
