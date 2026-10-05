import SwiftUI
import AVFoundation

struct MotionArtworkView: View {
    let videoURL: URL?
    let fallbackId: String
    let fallbackImage: PlatformImage?
    var cornerRadius: CGFloat = MinidiscCornerRadius.large
    var isPaused: Bool = false
    var aspectRatio: CGFloat? = 1
    var onReady: (() -> Void)? = nil

    @State private var isVideoReady: Bool

    init(
        videoURL: URL?,
        fallbackId: String,
        fallbackImage: PlatformImage? = nil,
        cornerRadius: CGFloat = MinidiscCornerRadius.large,
        isPaused: Bool = false,
        aspectRatio: CGFloat? = 1,
        onReady: (() -> Void)? = nil
    ) {
        self.videoURL = videoURL
        self.fallbackId = fallbackId
        self.fallbackImage = fallbackImage
        self.cornerRadius = cornerRadius
        self.isPaused = isPaused
        self.aspectRatio = aspectRatio
        self.onReady = onReady
        let isCached = videoURL.flatMap { MotionArtworkCache.shared.cachedURL(for: $0) } != nil
        _isVideoReady = State(initialValue: isCached)
    }

    var body: some View {
        Group {
            if let aspectRatio {
                content
                    .aspectRatio(aspectRatio, contentMode: .fit)
            } else {
                content
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .clipped()
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            if let videoURL, let firstFrame = MotionArtworkCache.shared.firstFrame(for: videoURL) {
                Image(platformImage: firstFrame)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                CoverArtView(
                    id: fallbackId,
                    size: 800,
                    tier: .hero,
                    cornerRadius: cornerRadius,
                    initialImage: fallbackImage
                )
                .aspectRatio(contentMode: .fill)
            }

            // Capa de video animado en bucle si existe URL
            if let videoURL {
                LoopingVideoPlayerRepresentable(videoURL: videoURL, isPaused: isPaused, onReady: {
                    if !isVideoReady {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isVideoReady = true
                        }
                    }
                    onReady?()
                })
                .opacity(isVideoReady ? 1.0 : 0.0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

// MARK: - Looping Video Player

private struct LoopingVideoPlayerRepresentable: UIViewRepresentable {
    let videoURL: URL
    let isPaused: Bool
    let onReady: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReady: onReady)
    }

    func makeUIView(context: Context) -> PlayerContainerUIView {
        let view = PlayerContainerUIView()
        context.coordinator.setup(url: videoURL, in: view)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerUIView, context: Context) {
        if context.coordinator.currentURL != videoURL {
            context.coordinator.setup(url: videoURL, in: uiView)
        }
        context.coordinator.setPaused(isPaused)
    }

    static func dismantleUIView(_ uiView: PlayerContainerUIView, coordinator: Coordinator) {
        coordinator.pauseForDismissal()
    }

    @MainActor
    final class Coordinator: NSObject {
        var currentURL: URL?
        private var player: AVPlayer?
        private var isUserPaused = false
        private var readyObserver: NSKeyValueObservation?
        private var readyForDisplayObserver: NSKeyValueObservation?
        private var endObserver: Any?
        private let onReady: () -> Void

        init(onReady: @escaping () -> Void) {
            self.onReady = onReady
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleBackground),
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleForeground),
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
        }

        func pauseForDismissal() {
            // Keep the current video frame on AVPlayerLayer during dismissal.
            // Do NOT remove the player from the layer, which would reveal the static cover.
            player?.pause()
            readyObserver?.invalidate()
            readyObserver = nil
            readyForDisplayObserver?.invalidate()
            readyForDisplayObserver = nil
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
        }

        private func cleanCurrentItem() {
            readyObserver?.invalidate()
            readyObserver = nil
            readyForDisplayObserver?.invalidate()
            readyForDisplayObserver = nil
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
            player?.pause()
            player = nil
        }

        func cleanup() {
            NotificationCenter.default.removeObserver(self)
            cleanCurrentItem()
        }

        func setup(url: URL, in view: PlayerContainerUIView) {
            let effectiveURL = MotionArtworkCache.shared.cachedURL(for: url) ?? url
            if let currentURL {
                let currentEffective = MotionArtworkCache.shared.cachedURL(for: currentURL) ?? currentURL
                if currentEffective == effectiveURL && player != nil {
                    self.currentURL = url
                    return
                }
            }

            currentURL = url
            cleanCurrentItem()

            if !url.isFileURL && effectiveURL == url {
                if !UserDefaults.standard.bool(forKey: "minidisc_data_saver_enabled") {
                    Task {
                        _ = try? await MotionArtworkCache.shared.loadOrDownload(for: url)
                    }
                }
            }

            let asset = AVURLAsset(url: effectiveURL)
            let item = AVPlayerItem(asset: asset)

            let avPlayer = AVPlayer(playerItem: item)
            avPlayer.isMuted = true
            avPlayer.volume = 0.0
            avPlayer.preventsDisplaySleepDuringVideoPlayback = false
            avPlayer.automaticallyWaitsToMinimizeStalling = true
            avPlayer.actionAtItemEnd = .none

            self.player = avPlayer
            view.playerLayer.player = avPlayer
            view.playerLayer.videoGravity = .resizeAspectFill

            readyObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                if item.status == .readyToPlay {
                    Task { @MainActor [weak self] in
                        if self?.isUserPaused == false {
                            self?.player?.play()
                        }
                    }
                }
            }

            readyForDisplayObserver = view.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                if layer.isReadyForDisplay {
                    Task { @MainActor [weak self] in
                        self?.onReady()
                    }
                }
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                    if !self.isUserPaused {
                        self.player?.play()
                    }
                }
            }

            if !isUserPaused {
                avPlayer.play()
            }
        }

        func setPaused(_ paused: Bool) {
            guard paused != isUserPaused else { return }
            isUserPaused = paused
            if paused {
                player?.pause()
            } else {
                player?.play()
            }
        }

        func play() {
            setPaused(false)
        }

        func pause() {
            setPaused(true)
        }

        @objc private func handleBackground() {
            player?.pause()
        }

        @objc private func handleForeground() {
            if !isUserPaused {
                player?.play()
            }
        }
    }
}

private class PlayerContainerUIView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.masksToBounds = true
        playerLayer.masksToBounds = true
        playerLayer.videoGravity = .resizeAspectFill
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
