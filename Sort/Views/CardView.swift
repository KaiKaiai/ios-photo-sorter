import SwiftUI
import Photos

/// One item on the sorting screen. The top card autoplays videos (muted) and plays
/// Live Photos while you press and hold; cards waiting behind only load their still,
/// from the phone.
struct CardView: View {
    let asset: PHAsset
    let isTop: Bool
    let isHoldingLive: Bool

    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var network = NetworkMonitor.shared
    @AppStorage(SettingsKey.downloadPolicy) private var policy: DownloadPolicy = .wifiOnly

    @StateObject private var imageLoader = AssetImageLoader()
    @StateObject private var videoLoader = VideoLoader()
    @StateObject private var liveLoader = LivePhotoLoader()

    private var isVideo: Bool { asset.mediaType == .video }
    private var isLive: Bool { asset.mediaSubtypes.contains(.photoLive) }
    private var downloadsAllowed: Bool { network.allowsDownloads(policy) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemBackground))

                if let image = imageLoader.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                }

                if isVideo, isTop, let player = videoLoader.player {
                    PlayerLayerView(player: player)
                }

                if isLive, let live = liveLoader.livePhoto {
                    LivePhotoView(livePhoto: live, isPlaying: isHoldingLive)
                        .opacity(isHoldingLive ? 1 : 0)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .topLeading) {
                badges
            }
            .overlay(alignment: .bottomTrailing) {
                if let value = imageLoader.progress ?? videoLoader.progress ?? liveLoader.progress {
                    ProgressRing(progress: value)
                        .frame(width: 34, height: 34)
                        .padding(12)
                }
            }
            .onAppear {
                refresh(size: geo.size)
            }
            .onChange(of: isTop) { _, _ in
                refresh(size: geo.size)
            }
            .onChange(of: isHoldingLive) { _, _ in
                refresh(size: geo.size)
            }
            .onChange(of: downloadsAllowed) { _, _ in
                refresh(size: geo.size)
            }
            .onChange(of: imageLoader.originalInCloud) { _, _ in
                refresh(size: geo.size)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && isTop {
                    videoLoader.resume()
                }
            }
            .onDisappear {
                imageLoader.cancel()
                videoLoader.stop()
                liveLoader.cancel()
            }
        }
    }

    private var badges: some View {
        HStack(spacing: 6) {
            if isLive {
                MediaBadge(text: "LIVE", systemImage: "livephoto")
            }
            if isVideo {
                MediaBadge(text: durationText, systemImage: "video.fill")
            }
            if imageLoader.originalInCloud || videoLoader.unavailable {
                MediaBadge(text: nil, systemImage: "icloud")
                    .accessibilityLabel("Original is in iCloud")
            }
        }
        .padding(10)
    }

    private var durationText: String {
        let total = asset.duration.isFinite ? Int(asset.duration.rounded()) : 0
        let seconds = total % 60
        return "\(total / 60):\(seconds < 10 ? "0" : "")\(seconds)"
    }

    private func pixelSize(for size: CGSize) -> CGSize {
        let width = size.width > 1 ? size.width : 390
        let height = size.height > 1 ? size.height : 600
        return CGSize(width: width * displayScale, height: height * displayScale)
    }

    /// Works out what this card should be loading right now. Only the card you're looking at
    /// may download from iCloud, and a Live Photo's moving part only downloads once you press and hold.
    private func refresh(size: CGSize) {
        let allow = downloadsAllowed
        let target = pixelSize(for: size)
        imageLoader.ensure(asset, targetSize: target, contentMode: .aspectFit, allowNetwork: isTop && allow)

        guard isTop else {
            videoLoader.stop()
            liveLoader.cancel()
            return
        }
        if isVideo {
            videoLoader.ensure(asset, allowNetwork: allow, muted: true, loops: true)
        } else if isLive {
            liveLoader.ensure(asset, targetSize: target, allowNetwork: allow && isHoldingLive)
        }
    }
}
