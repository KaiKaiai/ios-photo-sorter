import SwiftUI
import AVKit
import Photos

/// View-only full screen: zoom photos (Live Photos too, and press and hold to play them),
/// play videos with sound. Swipe down or tap the cross to go back; nothing here can delete or file.
struct FullScreenViewer: View {
    let asset: PHAsset

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @ObservedObject private var network = NetworkMonitor.shared
    @AppStorage(SettingsKey.downloadPolicy) private var policy: DownloadPolicy = .wifiOnly

    @StateObject private var imageLoader = AssetImageLoader()
    @StateObject private var videoLoader = VideoLoader()
    @StateObject private var liveLoader = LivePhotoLoader()
    @State private var isZoomed = false
    @State private var dragY: CGFloat = 0
    @State private var didLoad = false

    private var isVideo: Bool { asset.mediaType == .video }
    private var isLive: Bool { asset.mediaSubtypes.contains(.photoLive) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                    .ignoresSafeArea()
                    .opacity(1 - Double(min(dragY, 400)) / 800)
                content
                    .offset(y: dragY)
                    .scaleEffect(1 - min(dragY, 300) / 1500)
            }
            .overlay(alignment: .topTrailing) {
                closeButton
            }
            .overlay(alignment: .bottom) {
                infoRow
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                load(size: geo.size)
            }
        }
        .statusBarHidden()
        .simultaneousGesture(dismissGesture)
        .onDisappear {
            stopPlayback()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isVideo {
            if let player = videoLoader.player {
                VideoPlayer(player: player)
            } else if let image = imageLoader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .tint(.white)
            }
        } else if imageLoader.image != nil || liveLoader.livePhoto != nil {
            ZoomableMediaView(image: imageLoader.image, livePhoto: liveLoader.livePhoto, isZoomed: $isZoomed)
        } else {
            ProgressView()
                .tint(.white)
        }
    }

    private var closeButton: some View {
        Button {
            close()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.18), in: Circle())
        }
        .padding(.top, 8)
        .padding(.trailing, 16)
        .accessibilityLabel("Close")
    }

    private var infoRow: some View {
        HStack(spacing: 10) {
            if let date = asset.creationDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            if isLive {
                Label("Hold to play", systemImage: "livephoto")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
            }
            if imageLoader.originalInCloud || videoLoader.unavailable {
                Label("Original in iCloud", systemImage: "icloud")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
            }
            if let value = imageLoader.progress ?? videoLoader.progress ?? liveLoader.progress {
                ProgressRing(progress: value)
                    .frame(width: 26, height: 26)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.35), in: Capsule())
        .padding(.bottom, isVideo ? 70 : 16)
        .opacity(dragY > 0 || isZoomed ? 0 : 1)
        .allowsHitTesting(false)
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard !isZoomed else { return }
                let moved = value.translation
                // Only a mostly-downward drag closes, so scrubbing a video sideways never does.
                if dragY > 0 || (moved.height > 0 && moved.height > abs(moved.width)) {
                    dragY = max(0, moved.height)
                }
            }
            .onEnded { value in
                let moved = value.translation
                let wasClosing = dragY > 0
                let farEnough = moved.height > 120 || value.predictedEndTranslation.height > 420
                if wasClosing && !isZoomed && moved.height > abs(moved.width) && farEnough {
                    close()
                } else if dragY != 0 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragY = 0
                    }
                }
            }
    }

    private func close() {
        stopPlayback()
        dismiss()
    }

    /// Stops sound before the viewer goes, so any music you were playing picks up again.
    private func stopPlayback() {
        imageLoader.cancel()
        liveLoader.cancel()
        if isVideo {
            videoLoader.stop()
            AudioSession.useAmbient()
        }
    }

    private func load(size: CGSize) {
        let allow = network.allowsDownloads(policy)
        let width = max(size.width, 390) * displayScale * 2
        let height = max(size.height, 700) * displayScale * 2
        let target = CGSize(width: width, height: height)

        imageLoader.load(asset, targetSize: target, contentMode: .aspectFit, allowNetwork: allow)
        if isVideo {
            AudioSession.usePlayback()
            videoLoader.load(asset, allowNetwork: allow, muted: false, loops: false)
        } else if isLive {
            liveLoader.load(asset, targetSize: target, allowNetwork: allow)
        }
    }
}
