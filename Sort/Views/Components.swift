import SwiftUI
import Photos
import PhotosUI
import AVFoundation
import UIKit

/// A square thumbnail that fills its frame. Uses what's on the phone only.
struct AssetThumbnail: View {
    let asset: PHAsset
    var pixelSide: CGFloat = 180

    @StateObject private var loader = AssetImageLoader()

    var body: some View {
        Color(.tertiarySystemFill)
            .overlay {
                if let image = loader.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if asset.mediaType == .video {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .padding(4)
                }
            }
            .onAppear {
                loader.load(
                    asset,
                    targetSize: CGSize(width: pixelSide, height: pixelSide),
                    contentMode: .aspectFill,
                    allowNetwork: false
                )
            }
            .onDisappear {
                loader.cancel()
            }
    }
}

/// A bare video surface with no controls, for cards.
final class PlayerSurfaceView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // layerClass guarantees this cast.
        layer as! AVPlayerLayer
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: PlayerSurfaceView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}

/// Plays a Live Photo on a card while `isPlaying` is true. Touches pass straight through.
struct LivePhotoView: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    var isPlaying: Bool

    final class Coordinator {
        var isPlaying = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.livePhoto = livePhoto
        view.isUserInteractionEnabled = false
        view.playbackGestureRecognizer.isEnabled = false
        return view
    }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        if view.livePhoto !== livePhoto {
            view.livePhoto = livePhoto
        }
        guard context.coordinator.isPlaying != isPlaying else { return }
        context.coordinator.isPlaying = isPlaying
        if isPlaying {
            view.startPlayback(with: .full)
        } else {
            view.stopPlayback()
        }
    }
}

/// Full-screen photo: pinch or double-tap to zoom, press and hold to play a Live Photo.
/// Panning only turns on once zoomed, so a swipe down at normal size still closes the viewer.
struct ZoomableMediaView: UIViewRepresentable {
    let image: UIImage?
    let livePhoto: PHLivePhoto?
    @Binding var isZoomed: Bool

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableMediaView
        let container: UIView
        let imageView: UIImageView
        let liveView: PHLivePhotoView
        var isPlayingLive = false

        init(parent: ZoomableMediaView) {
            self.parent = parent
            container = UIView()
            imageView = UIImageView()
            liveView = PHLivePhotoView()
            super.init()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            container
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let zoomed = scrollView.zoomScale > 1.01
            scrollView.panGestureRecognizer.isEnabled = zoomed
            if parent.isZoomed != zoomed {
                parent.isZoomed = zoomed
            }
        }

        /// The Live Photo layer only shows while playing, or when it's all there is to show.
        func updateLiveVisibility() {
            let onlyLive = parent.image == nil && liveView.livePhoto != nil
            liveView.alpha = (isPlayingLive || onlyLive) ? 1 : 0
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = recognizer.location(in: container)
                let width = scrollView.bounds.width / 2.5
                let height = scrollView.bounds.height / 2.5
                let rect = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
                scrollView.zoom(to: rect, animated: true)
            }
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                guard liveView.livePhoto != nil else { return }
                isPlayingLive = true
                updateLiveVisibility()
                liveView.startPlayback(with: .full)
            case .ended, .cancelled, .failed:
                guard isPlayingLive else { return }
                isPlayingLive = false
                liveView.stopPlayback()
                updateLiveVisibility()
            default:
                break
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let coordinator = context.coordinator
        let scrollView = UIScrollView()
        scrollView.delegate = coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        scrollView.panGestureRecognizer.isEnabled = false

        let container = coordinator.container
        container.frame = scrollView.bounds
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let stacked: [UIView] = [coordinator.imageView, coordinator.liveView]
        for subview in stacked {
            subview.frame = container.bounds
            subview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            subview.contentMode = .scaleAspectFit
            subview.clipsToBounds = true
            container.addSubview(subview)
        }
        coordinator.liveView.alpha = 0
        coordinator.liveView.isUserInteractionEnabled = false
        coordinator.liveView.playbackGestureRecognizer.isEnabled = false
        scrollView.addSubview(container)

        let doubleTap = UITapGestureRecognizer(
            target: coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let hold = UILongPressGestureRecognizer(
            target: coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        hold.minimumPressDuration = 0.25
        scrollView.addGestureRecognizer(hold)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.imageView.image !== image {
            coordinator.imageView.image = image
        }
        if coordinator.liveView.livePhoto !== livePhoto {
            coordinator.liveView.livePhoto = livePhoto
        }
        coordinator.updateLiveVisibility()
    }
}

/// A small ring shown while an original downloads from iCloud.
struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: max(0.03, progress))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(5)
        .background(Color.black.opacity(0.4), in: Circle())
        .animation(.linear(duration: 0.2), value: progress)
    }
}

/// The small capsules on a card: LIVE, video length, cloud.
struct MediaBadge: View {
    var text: String?
    let systemImage: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            if let text {
                Text(text)
                    .monospacedDigit()
            }
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

/// Shows the store's error message as an alert. Only the screen on top should enable it.
struct LibraryErrorAlert: ViewModifier {
    @EnvironmentObject private var library: LibraryStore
    var isEnabled: Bool

    func body(content: Content) -> some View {
        content.alert("Something went wrong", isPresented: isShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.alertMessage ?? "")
        }
    }

    private var isShown: Binding<Bool> {
        Binding(
            get: { isEnabled && library.alertMessage != nil },
            set: { shown in
                if !shown { library.alertMessage = nil }
            }
        )
    }
}

extension View {
    func libraryErrorAlert(isEnabled: Bool = true) -> some View {
        modifier(LibraryErrorAlert(isEnabled: isEnabled))
    }
}
