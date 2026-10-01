import SwiftUI
import AVFoundation

struct MotionArtworkView: View {
    let videoURL: URL?
    let fallbackId: String
    let fallbackImage: PlatformImage?
    var cornerRadius: CGFloat = MinidiscCornerRadius.large
    var isPaused: Bool = false
    var aspectRatio: CGFloat? = 1

    @State private var isVideoReady = false

    init(
        videoURL: URL?,
        fallbackId: String,
        fallbackImage: PlatformImage? = nil,
        cornerRadius: CGFloat = MinidiscCornerRadius.large,
        isPaused: Bool = false,
        aspectRatio: CGFloat? = 1
    ) {
        self.videoURL = videoURL
        self.fallbackId = fallbackId
        self.fallbackImage = fallbackImage
        self.cornerRadius = cornerRadius
        self.isPaused = isPaused
        self.aspectRatio = aspectRatio
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
        .onChange(of: videoURL) { _, _ in
            isVideoReady = false
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            // Capa estática base de la portada (siempre presente para transición suave y mientras carga el video)
            CoverArtView(
                id: fallbackId,
                size: 800,
                tier: .hero,
                cornerRadius: cornerRadius,
                initialImage: fallbackImage
            )

            // Capa de video animado en bucle si existe URL
            if let videoURL {
                LoopingVideoPlayerRepresentable(videoURL: videoURL, isPaused: isPaused, onReady: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isVideoReady = true
                    }
                })
                .id(videoURL)
                .opacity(isVideoReady ? 1.0 : 0.0)
            }
        }
    }
}

// MARK: - Looping Video Player (AVPlayerLooper + AVQueuePlayer)

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
        if isPaused {
            context.coordinator.pause()
        } else {
            context.coordinator.play()
        }
    }

    static func dismantleUIView(_ uiView: PlayerContainerUIView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    final class Coordinator: NSObject {
        var currentURL: URL?
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var isUserPaused = false
        private var readyObserver: NSKeyValueObservation?
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

        func cleanup() {
            NotificationCenter.default.removeObserver(self)
            readyObserver?.invalidate()
            readyObserver = nil
            player?.pause()
            player = nil
            looper = nil
        }

        func setup(url: URL, in view: PlayerContainerUIView) {
            currentURL = url
            readyObserver?.invalidate()
            player?.pause()
            player = nil
            looper = nil

            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)

            let qPlayer = AVQueuePlayer()
            qPlayer.isMuted = true
            qPlayer.volume = 0.0
            qPlayer.preventsDisplaySleepDuringVideoPlayback = false
            qPlayer.actionAtItemEnd = .none

            self.looper = AVPlayerLooper(player: qPlayer, templateItem: item)
            self.player = qPlayer
            view.playerLayer.player = qPlayer
            view.playerLayer.videoGravity = .resizeAspectFill

            readyObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                if item.status == .readyToPlay {
                    DispatchQueue.main.async {
                        self?.onReady()
                        if self?.isUserPaused == false {
                            self?.player?.play()
                        }
                    }
                }
            }

            if !isUserPaused {
                qPlayer.play()
            }
        }

        func play() {
            isUserPaused = false
            player?.play()
        }

        func pause() {
            isUserPaused = true
            player?.pause()
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
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
