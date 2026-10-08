import SwiftUI

/// The same two queue actions are available on every song row. Lists support them on iOS 26;
/// scroll-based detail pages opt into the native swipe coordinator on iOS 27.
struct SongQuickActions: ViewModifier {
    let song: DisplayableSong
    var onAddToPlaylist: ((DisplayableSong) -> Void)?
    var onRemove: (() -> Void)? = nil
    @Environment(\.appContainer) private var container
    @Environment(PlaylistAddition.self) private var playlistAddition: PlaylistAddition?

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if container?.playerState.isLiveStream != true {
                    Button {
                        HapticFeedback.light.trigger()
                        Task { await container?.playerService.playNext(song) }
                    } label: {
                        Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    }
                    .tint(.purple)
                    .accessibilityLabel("Play Next")

                    Button {
                        HapticFeedback.light.trigger()
                        Task { await container?.playerService.addToQueue(song) }
                    } label: {
                        Image(systemName: "text.append")
                    }
                    .tint(.orange)
                    .accessibilityLabel("Add to Queue")
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let onRemove {
                    Button(role: .destructive, action: onRemove) {
                        Label("Remove from Queue", systemImage: "minus.circle")
                    }
                } else if !song.isLocalFile {
                    Button {
                        if let onAddToPlaylist { onAddToPlaylist(song) }
                        else { playlistAddition?.present(song) }
                    } label: {
                        Label("Add to Playlist...", systemImage: "music.note.list")
                    }
                    .tint(Color.minidiscAccent)
                    .disabled(container?.serverState.isOnline != true || (onAddToPlaylist == nil && playlistAddition == nil))
                }
            }
    }
}

private struct SongSwipeContainer: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        // The SDK 27 coordinator also needs a compile-time guard for older Xcode archives.
        #if compiler(>=6.4)
        if #available(iOS 27, macOS 27, *) {
            content.swipeActionsContainer()
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    func minidiscSongSwipeContainer() -> some View { modifier(SongSwipeContainer()) }
}

// MARK: - Reusable Swipe Action Components for Non-List Views

struct SongLeadingSwipeActionButtons: View {
    let song: DisplayableSong
    let totalWidth: CGFloat
    let rowHeight: CGFloat
    let onPlayNext: () -> Void
    let onAddToQueue: () -> Void

    static let standardButtonWidth: CGFloat = 74

    var body: some View {
        let total = max(0, totalWidth)
        let button2Width: CGFloat = total < Self.standardButtonWidth * 2 ? (total / 2) : Self.standardButtonWidth
        let button1Width: CGFloat = max(0, total - button2Width)

        HStack(spacing: 0) {
            Button {
                HapticFeedback.light.trigger()
                onPlayNext()
            } label: {
                ZStack {
                    Color.purple
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: button1Width, height: rowHeight)
            }
            .buttonStyle(.plain)
            .frame(width: button1Width, height: rowHeight)
            .clipped()
            .accessibilityLabel("Play Next")

            Button {
                HapticFeedback.light.trigger()
                onAddToQueue()
            } label: {
                ZStack {
                    Color.orange
                    Image(systemName: "text.append")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: button2Width, height: rowHeight)
            }
            .buttonStyle(.plain)
            .frame(width: button2Width, height: rowHeight)
            .clipped()
            .accessibilityLabel("Add to Queue")
        }
        .frame(width: total, height: rowHeight)
        .clipped()
    }
}

/// A container that provides horizontal swipe-to-reveal queue actions (Play Next & Add to Queue)
/// for views inside a ScrollView, exactly matching the native List swipe actions.
struct SwipeableSongRow<Content: View>: View {
    let song: DisplayableSong
    let isLiveStream: Bool
    @Binding var swipedSongId: String?
    let onPlayNext: () -> Void
    let onAddToQueue: () -> Void
    let onTap: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var dragOffset: CGFloat = 0
    @State private var baseOffset: CGFloat = 0
    @State private var isDraggingHorizontal: Bool = false
    @State private var hasTriggeredFullSwipeHaptic: Bool = false
    @State private var rowHeight: CGFloat = 52

    private let revealWidth: CGFloat = SongLeadingSwipeActionButtons.standardButtonWidth * 2
    private let fullSwipeThreshold: CGFloat = 180

    var body: some View {
        ZStack(alignment: .leading) {
            if dragOffset > 0 {
                SongLeadingSwipeActionButtons(
                    song: song,
                    totalWidth: dragOffset,
                    rowHeight: rowHeight,
                    onPlayNext: {
                        onPlayNext()
                        close()
                    },
                    onAddToQueue: {
                        onAddToQueue()
                        close()
                    }
                )
            }

            content()
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { rowHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, newH in rowHeight = newH }
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if dragOffset > 0 {
                        close()
                    } else {
                        onTap()
                    }
                }
                .offset(x: dragOffset)
        }
        .contentShape(Rectangle())
        .clipped()
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard !isLiveStream else { return }
                    let tx = value.translation.width
                    let ty = value.translation.height

                    if !isDraggingHorizontal {
                        if abs(ty) > abs(tx) {
                            return
                        }
                        if tx < 0 && baseOffset == 0 {
                            return
                        }
                        isDraggingHorizontal = true
                        if swipedSongId != song.id {
                            swipedSongId = song.id
                        }
                    }

                    guard isDraggingHorizontal else { return }
                    let raw = baseOffset + tx
                    dragOffset = max(0, raw)

                    if dragOffset >= fullSwipeThreshold {
                        if !hasTriggeredFullSwipeHaptic {
                            HapticFeedback.light.trigger()
                            hasTriggeredFullSwipeHaptic = true
                        }
                    } else {
                        hasTriggeredFullSwipeHaptic = false
                    }
                }
                .onEnded { value in
                    guard !isLiveStream, isDraggingHorizontal else { return }
                    isDraggingHorizontal = false
                    hasTriggeredFullSwipeHaptic = false

                    let finalOffset = dragOffset

                    if finalOffset >= fullSwipeThreshold {
                        HapticFeedback.light.trigger()
                        onPlayNext()
                        baseOffset = 0
                        swipedSongId = nil
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    } else if finalOffset >= 60 {
                        baseOffset = revealWidth
                        swipedSongId = song.id
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            dragOffset = revealWidth
                        }
                    } else {
                        baseOffset = 0
                        if swipedSongId == song.id {
                            swipedSongId = nil
                        }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onChange(of: swipedSongId) { _, newId in
            if newId != song.id && (dragOffset > 0 || baseOffset > 0) {
                baseOffset = 0
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    dragOffset = 0
                }
            }
        }
    }

    private func close() {
        baseOffset = 0
        if swipedSongId == song.id {
            swipedSongId = nil
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            dragOffset = 0
        }
    }
}
