import SwiftUI
import SwiftSonic

struct LyricsView: View {
    @Bindable var viewModel: LyricsViewModel
    var areControlsHidden: Bool = false

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loadedTTML(let ttml):
                TTMLLyricsView(viewModel: viewModel, lyricsResponse: ttml, areControlsHidden: areControlsHidden)

            case .loaded(let structured):
                loadedContent(structured)

            case .empty:
                emptyState

            case .unsupported:
                unsupportedState

            case .error(let message):
                errorState(message)
            }
        }
        .id(ObjectIdentifier(viewModel))
        .onAppear { viewModel.setVisible(true) }
        .onDisappear { viewModel.setVisible(false) }
        .onChange(of: viewModel.isPlaying) { _, _ in viewModel.reconcileTracking() }
    }

    // MARK: - Loaded

    @ViewBuilder
    private func loadedContent(_ structured: StructuredLyrics) -> some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(Array(structured.line.enumerated()), id: \.offset) { index, line in
                            LyricsLineView(
                                value: line.value,
                                index: index,
                                currentIndex: viewModel.currentLineIndex,
                                isSynced: structured.synced,
                                isTappable: structured.synced && line.start != nil,
                                onTap: { viewModel.userTapped(lineIndex: index) }
                            )
                            .id(index)
                        }
                    }
                    .padding(.horizontal, MinidiscSpacing.l)
                    .padding(.top, 56)
                    .padding(.bottom, max(750, geo.size.height * 0.90))
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    if let currentIndex = viewModel.currentLineIndex {
                        proxy.scrollTo(currentIndex, anchor: lyricsAnchor(for: currentIndex, in: geo.size.height))
                    }
                }
                .task {
                    try? await Task.sleep(for: .milliseconds(60))
                    guard !Task.isCancelled, !viewModel.isUserScrolling else { return }
                    if let currentIndex = viewModel.currentLineIndex {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(currentIndex, anchor: lyricsAnchor(for: currentIndex, in: geo.size.height))
                        }
                    }
                }
                .onChange(of: viewModel.currentLineIndex) { _, newIndex in
                    guard viewModel.autoScrollEnabled,
                          !viewModel.isUserScrolling,
                          let newIndex else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newIndex, anchor: lyricsAnchor(for: newIndex, in: geo.size.height))
                    }
                }
                .onChange(of: viewModel.isUserScrolling) { _, isScrolling in
                    guard viewModel.autoScrollEnabled,
                          !isScrolling,
                          let currentIndex = viewModel.currentLineIndex else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(currentIndex, anchor: lyricsAnchor(for: currentIndex, in: geo.size.height))
                    }
                }
                .onChange(of: areControlsHidden) { _, _ in
                    guard viewModel.autoScrollEnabled,
                          !viewModel.isUserScrolling,
                          let currentIndex = viewModel.currentLineIndex else { return }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        proxy.scrollTo(currentIndex, anchor: lyricsAnchor(for: currentIndex, in: geo.size.height))
                    }
                }
                .onChange(of: geo.size.height) { _, newHeight in
                    guard viewModel.autoScrollEnabled,
                          !viewModel.isUserScrolling,
                          let currentIndex = viewModel.currentLineIndex else { return }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        proxy.scrollTo(currentIndex, anchor: lyricsAnchor(for: currentIndex, in: newHeight))
                    }
                }
                .onScrollPhaseChange { _, newPhase in
                    switch newPhase {
                    case .interacting, .tracking:
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

    private func lyricsAnchor(for index: Int?, in containerHeight: CGFloat) -> UnitPoint {
        let fullHeight = areControlsHidden ? containerHeight : (containerHeight + 270.0)
        let targetTopOffset = 0.090 * fullHeight
        let anchorY = targetTopOffset / max(1.0, containerHeight)
        return UnitPoint(x: 0.5, y: anchorY)
    }



    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No lyrics available")
                .font(.minidiscDetailTitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unsupportedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Lyrics not supported")
                .font(.minidiscDetailTitle)
                .foregroundStyle(.secondary)
            Text("Update your Navidrome server to enable the songLyrics extension")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.octagon")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Failed to load lyrics")
                .font(.minidiscDetailTitle)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }


}
