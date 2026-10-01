import SwiftUI
import Photos
import AVFoundation

/// Loads a still image for an asset. With iCloud downloads allowed, Photos fetches the
/// original when needed and reports progress; otherwise it serves what's on the phone.
@MainActor
final class AssetImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var progress: Double?
    /// The requested quality isn't on the phone and downloading wasn't allowed.
    @Published private(set) var originalInCloud = false

    private var requestID: PHImageRequestID = PHInvalidImageRequestID
    private var generation = 0
    private var gotFinal = false
    private var hasRequested = false
    private var requestedNetwork = false

    /// Starts loading if nothing is loaded yet, asks again with iCloud once that's allowed,
    /// and stops a download for an item you've moved past (keeping what's on screen).
    func ensure(_ asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode, allowNetwork: Bool) {
        if !hasRequested {
            load(asset, targetSize: targetSize, contentMode: contentMode, allowNetwork: allowNetwork)
        } else if allowNetwork && !requestedNetwork && (originalInCloud || image == nil) {
            load(asset, targetSize: targetSize, contentMode: contentMode, allowNetwork: true)
        } else if !allowNetwork && requestedNetwork && progress != nil {
            load(asset, targetSize: targetSize, contentMode: contentMode, allowNetwork: false)
        }
    }

    func load(_ asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode, allowNetwork: Bool) {
        cancel()
        hasRequested = true
        requestedNetwork = allowNetwork
        let token = generation
        gotFinal = false
        progress = nil
        originalInCloud = false

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = allowNetwork
        options.progressHandler = { @Sendable value, _, _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, !self.gotFinal else { return }
                self.progress = value < 1 ? value : nil
            }
        }

        requestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { @Sendable image, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                if let image, !(degraded && self.gotFinal) {
                    self.image = image
                }
                if !degraded {
                    self.gotFinal = true
                    self.progress = nil
                    self.requestID = PHInvalidImageRequestID
                }
                self.originalInCloud = inCloud && !allowNetwork
            }
        }
    }

    func cancel() {
        generation += 1
        hasRequested = false
        progress = nil
        if requestID != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(requestID)
            requestID = PHInvalidImageRequestID
        }
    }
}

/// Loads a video into a player. Cards use it muted and looping; full screen uses it with sound.
@MainActor
final class VideoLoader: ObservableObject {
    @Published private(set) var player: AVQueuePlayer?
    @Published private(set) var progress: Double?
    /// The video isn't on the phone and downloading wasn't allowed.
    @Published private(set) var unavailable = false

    private var looper: AVPlayerLooper?
    private var requestID: PHImageRequestID = PHInvalidImageRequestID
    private var generation = 0
    private var hasRequested = false
    private var requestedNetwork = false

    /// Starts loading if needed, and asks again with iCloud once that's allowed.
    func ensure(_ asset: PHAsset, allowNetwork: Bool, muted: Bool, loops: Bool) {
        if player != nil { return }
        if hasRequested && (requestedNetwork || !allowNetwork) { return }
        load(asset, allowNetwork: allowNetwork, muted: muted, loops: loops)
    }

    func load(_ asset: PHAsset, allowNetwork: Bool, muted: Bool, loops: Bool) {
        stop()
        hasRequested = true
        requestedNetwork = allowNetwork
        let token = generation

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = allowNetwork
        options.deliveryMode = .automatic
        options.progressHandler = { @Sendable value, _, _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.player == nil else { return }
                self.progress = value < 1 ? value : nil
            }
        }

        requestID = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { @Sendable item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.requestID = PHInvalidImageRequestID
                self.progress = nil
                guard let item else {
                    self.unavailable = true
                    return
                }
                self.unavailable = false
                let player = AVQueuePlayer()
                player.isMuted = muted
                if loops {
                    self.looper = AVPlayerLooper(player: player, templateItem: item)
                } else {
                    // Stay on the last frame at the end, so you can scrub back and replay.
                    player.actionAtItemEnd = .pause
                    player.insert(item, after: nil)
                }
                self.player = player
                player.play()
            }
        }
    }

    /// Restarts a player that iOS paused, for example after the app was in the background.
    func resume() {
        player?.play()
    }

    func stop() {
        generation += 1
        hasRequested = false
        requestedNetwork = false
        if requestID != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(requestID)
            requestID = PHInvalidImageRequestID
        }
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
        progress = nil
        unavailable = false
    }
}

/// Loads the moving part of a Live Photo.
@MainActor
final class LivePhotoLoader: ObservableObject {
    @Published private(set) var livePhoto: PHLivePhoto?
    @Published private(set) var progress: Double?

    private var requestID: PHImageRequestID = PHInvalidImageRequestID
    private var generation = 0
    private var isRequesting = false
    private var requestedNetwork = false
    /// The last on-phone request found the moving part only in iCloud.
    private var needsDownload = false

    /// Starts loading if needed, and asks again with iCloud once that's allowed.
    func ensure(_ asset: PHAsset, targetSize: CGSize, allowNetwork: Bool) {
        if livePhoto != nil { return }
        if isRequesting {
            if allowNetwork && !requestedNetwork {
                load(asset, targetSize: targetSize, allowNetwork: true)
            }
            return
        }
        if needsDownload && !allowNetwork { return }
        load(asset, targetSize: targetSize, allowNetwork: allowNetwork)
    }

    func load(_ asset: PHAsset, targetSize: CGSize, allowNetwork: Bool) {
        cancel()
        let token = generation
        isRequesting = true
        requestedNetwork = allowNetwork

        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = allowNetwork
        options.progressHandler = { @Sendable value, _, _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.livePhoto == nil else { return }
                self.progress = value < 1 ? value : nil
            }
        }

        requestID = PHImageManager.default().requestLivePhoto(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { @Sendable live, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                if let live {
                    self.livePhoto = live
                    self.needsDownload = false
                }
                if !degraded {
                    self.isRequesting = false
                    self.progress = nil
                    self.requestID = PHInvalidImageRequestID
                    if live == nil && !cancelled {
                        self.needsDownload = inCloud
                    }
                }
            }
        }
    }

    func cancel() {
        generation += 1
        isRequesting = false
        progress = nil
        if requestID != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(requestID)
            requestID = PHInvalidImageRequestID
        }
    }
}
