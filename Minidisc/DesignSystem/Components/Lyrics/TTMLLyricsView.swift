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

// MARK: - Word Span View (Karaoke Lighting & Elevation)

struct TTMLWordSpanView: View {
    let word: NowLocalLyricWord
    let currentTime: Double
    let isLineActive: Bool
    var font: Font = .system(size: 28, weight: .bold, design: .rounded)

    var body: some View {
        let isSung = currentTime >= (word.endTime ?? (word.time + 0.35))
        let isSinging = currentTime >= word.time && !isSung
        let duration = max(0.06, (word.endTime ?? (word.time + 0.35)) - word.time)
        let progress = isSung ? 1.0 : (isSinging ? max(0.0, min(1.0, (currentTime - word.time) / duration)) : 0.0)

        ZStack(alignment: .leading) {
            // Base un-sung text
            Text(word.text)
                .font(font)
                .foregroundStyle(Color.white.opacity(isLineActive ? 0.38 : 0.25))

            // Lit active karaoke text with wipe mask
            if isLineActive && (isSinging || isSung) {
                Text(word.text)
                    .font(font)
                    .foregroundStyle(Color.white)
                    .shadow(color: .white.opacity(isSinging ? 0.35 : 0.0), radius: isSinging ? 5 : 0)
                    .mask(
                        GeometryReader { geo in
                            Rectangle()
                                .frame(width: isSung ? geo.size.width : geo.size.width * CGFloat(progress))
                        }
                    )
            }
        }
        .offset(y: (isLineActive && isSinging) ? -1.0 : 0.0)
        .animation(.easeOut(duration: 0.15), value: isSinging)
    }
}

// MARK: - TTMLLineContentView (Main vocals & optional adlibs)

struct TTMLLineContentView: View {
    let line: NowLocalLyricLine
    let currentTime: Double
    let isLineActive: Bool
    let isV2: Bool
    let hasWordSync: Bool

    private var alignment: HorizontalAlignment {
        isV2 ? .trailing : .leading
    }

    var body: some View {
        VStack(alignment: alignment, spacing: isLineActive ? 6 : 2) {
            // Main vocals
            if let mainWords = line.main?.words, !mainWords.isEmpty, hasWordSync {
                LyricsFlowLayout(horizontalAlignment: alignment) {
                    ForEach(mainWords) { w in
                        TTMLWordSpanView(
                            word: w,
                            currentTime: currentTime,
                            isLineActive: isLineActive,
                            font: .system(size: 28, weight: .bold, design: .rounded)
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
                            font: .system(size: 28, weight: .bold, design: .rounded)
                        )
                    }
                }
            } else {
                Text(line.main?.text ?? line.text)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(isLineActive ? Color.white : Color.white.opacity(0.4))
                    .multilineTextAlignment(isV2 ? .trailing : .leading)
            }

            // Adlibs vocals (if present)
            if line.hasAdlib == true, let adlib = line.adlib {
                if let adlibWords = adlib.words, !adlibWords.isEmpty, hasWordSync {
                    LyricsFlowLayout(horizontalAlignment: alignment) {
                        ForEach(adlibWords) { w in
                            TTMLWordSpanView(
                                word: w,
                                currentTime: currentTime,
                                isLineActive: isLineActive,
                                font: .system(size: 21, weight: .bold, design: .rounded)
                            )
                        }
                    }
                    .opacity(isLineActive ? 0.85 : 0.35)
                } else if let adlibText = adlib.text, !adlibText.isEmpty {
                    Text(adlibText)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(isLineActive ? Color.white.opacity(0.85) : Color.white.opacity(0.35))
                        .multilineTextAlignment(isV2 ? .trailing : .leading)
                }
            }
        }
    }
}

// MARK: - Single Line Container (Spatial layout v1/v2, physics, blur, scale)

struct TTMLLyricsLineView: View {
    let line: NowLocalLyricLine
    let index: Int
    let currentIndex: Int?
    let currentTime: Double
    let nextLineTime: Double?
    let hasMultiArtist: Bool
    let hasWordSync: Bool
    let onSeek: () -> Void

    private var isV2: Bool {
        line.agent == "v2"
    }

    private var isDotMarker: Bool {
        line.text == "…" || line.text == "..."
    }

    private var distance: Int {
        guard let currentIndex else { return 0 }
        return abs(index - currentIndex)
    }

    private var isLineActive: Bool {
        currentIndex == index
    }

    private var blurRadius: CGFloat {
        guard currentIndex != nil else { return 0 }
        if isLineActive { return 0 }
        switch distance {
        case 1: return 1.0
        case 2: return 2.5
        default: return 5.0
        }
    }

    private var opacity: Double {
        guard currentIndex != nil else { return 1.0 }
        if isLineActive { return 1.0 }
        if let cur = currentIndex, index < cur {
            return 0.35
        }
        switch distance {
        case 1: return 0.55
        case 2: return 0.38
        default: return 0.22
        }
    }

    private var scale: CGFloat {
        guard currentIndex != nil else { return 1.0 }
        return isLineActive ? 1.03 : (distance > 2 ? 0.96 : 1.0)
    }

    var body: some View {
        Group {
            if isDotMarker {
                let nextT = nextLineTime ?? (line.time + 8.0)
                ThreeDotsView(
                    currentTime: currentTime,
                    startTime: line.time,
                    nextTime: nextT,
                    isAgentV2: isV2
                )
            } else {
                TTMLLineContentView(
                    line: line,
                    currentTime: currentTime,
                    isLineActive: isLineActive,
                    isV2: isV2,
                    hasWordSync: hasWordSync
                )
                .frame(maxWidth: .infinity, alignment: isV2 ? .trailing : .leading)
                .padding(.leading, (hasMultiArtist && isV2) ? 44 : 0)
                .padding(.trailing, (hasMultiArtist && !isV2) ? 44 : 0)
                .opacity(opacity)
                .blur(radius: blurRadius)
                .scaleEffect(scale, anchor: isV2 ? .trailing : .leading)
                .animation(.easeInOut(duration: 0.3), value: currentIndex)
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 36) {
                    ForEach(Array(lyricsResponse.lyrics.enumerated()), id: \.offset) { index, line in
                        let nextLineTime = (index + 1 < lyricsResponse.lyrics.count) ? lyricsResponse.lyrics[index + 1].time : nil

                        TTMLLyricsLineView(
                            line: line,
                            index: index,
                            currentIndex: viewModel.currentLineIndex,
                            currentTime: viewModel.currentPosition,
                            nextLineTime: nextLineTime,
                            hasMultiArtist: hasMultiArtist,
                            hasWordSync: hasWordSync,
                            onSeek: {
                                viewModel.userTapped(seconds: line.time)
                            }
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 220)
            }
            .scrollIndicators(.hidden)
            .onChange(of: viewModel.currentLineIndex) { _, newIndex in
                guard viewModel.autoScrollEnabled,
                      !viewModel.isUserScrolling,
                      let newIndex else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(newIndex, anchor: .center)
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
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    if let composer = lyricsResponse.composer, !composer.isEmpty {
                        Text(composer)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        viewModel.autoScrollEnabled.toggle()
                    } label: {
                        Image(systemName: viewModel.autoScrollEnabled
                            ? "arrow.up.arrow.down.circle.fill"
                            : "arrow.up.arrow.down.circle")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            }
        }
    }
}
