import SwiftUI
import SwiftSonic

struct LyricsView: View {
    @Bindable var viewModel: LyricsViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loadedTTML(let ttml):
                TTMLLyricsView(viewModel: viewModel, lyricsResponse: ttml)

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
        .onAppear { viewModel.setVisible(true) }
        .onDisappear { viewModel.setVisible(false) }
        .onChange(of: viewModel.isPlaying) { _, _ in viewModel.reconcileTracking() }
    }

    // MARK: - Loaded

    @ViewBuilder
    private func loadedContent(_ structured: StructuredLyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
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
                .padding(.top, 38)
                .padding(.bottom, 220)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                if let currentIndex = viewModel.currentLineIndex {
                    let anchor = UnitPoint(x: 0.5, y: 0.08)
                    proxy.scrollTo(currentIndex, anchor: anchor)
                }
            }
            .onChange(of: viewModel.currentLineIndex) { _, newIndex in
                guard viewModel.autoScrollEnabled,
                      !viewModel.isUserScrolling,
                      let newIndex else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    let anchor = UnitPoint(x: 0.5, y: 0.08)
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
