import SwiftUI
import AVFoundation

public struct MotionArtworkView: View {
    let videoURL: URL?
    let fallbackId: String
    let fallbackImage: PlatformImage?
    var cornerRadius: CGFloat = MinidiscCornerRadius.large
    var isPaused: Bool = false

    @State private var isVideoReady = false

    public init(
        videoURL: URL?,
        fallbackId: String,
        fallbackImage: PlatformImage? = nil,
        cornerRadius: CGFloat = MinidiscCornerRadius.large,
        isPaused: Bool = false
    ) {
        self.videoURL = videoURL
        self.fallbackId = fallbackId
        self.fallbackImage = fallbackImage
        self.cornerRadius = cornerRadius
        self.isPaused = isPaused
    }

    public var body: some View {
        ZStack {
            // Capa estática base de la portada (siempre presente para transición suave y mientras carga el video)
            CoverArtView(
                id: fallbackId,
                size: 800,
                tier: .hero,
                cornerRadius: cornerRadius,
                initialImage: fallbackImage
            )
            .aspectRatio(1, contentMode: .fit)

            // Capa de video animado en bucle si existe URL
            if let videoURL {
                LoopingVideoPlayerRepresentable(videoURL: videoURL, isPaused: isPaused, onReady: {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        isVideoReady = true
                    }
                })
                .aspectRatio(1, contentMode: .fill)
                .opacity(isVideoReady ? 1.0 : 0.0)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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

    class Coordinator: NSObject {
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

        deinit {
            NotificationCenter.default.removeObserver(self)
            readyObserver?.invalidate()
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

            // Deshabilitar cualquier pista de audio para no interferir con la música
            for track in item.tracks {
                if track.assetTrack?.mediaType == .audio {
                    track.isEnabled = false
                }
            }

            let qPlayer = AVQueuePlayer(playerItem: item)
            qPlayer.isMuted = true
            qPlayer.volume = 0.0
            qPlayer.preventsDisplaySleepDuringVideoPlayback = false

            self.looper = AVPlayerLooper(player: qPlayer, templateItem: item)
            self.player = qPlayer
            view.playerLayer.player = qPlayer
            view.playerLayer.videoGravity = .resizeAspectFill

            readyObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                if item.status == .readyToPlay {
                    DispatchQueue.main.async {
                        self?.onReady()
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

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
