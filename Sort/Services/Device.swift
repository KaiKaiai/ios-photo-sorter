import Foundation
import Network
import AVFoundation
import UIKit

/// Watches the connection so iCloud downloads follow the Settings choice.
final class NetworkMonitor: ObservableObject, @unchecked Sendable {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected = true
    @Published private(set) var isExpensive = false

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            // Mobile data and personal hotspots count as expensive.
            let expensive = path.isExpensive
            guard let self else { return }
            DispatchQueue.main.async {
                self.isConnected = connected
                self.isExpensive = expensive
            }
        }
        monitor.start(queue: DispatchQueue(label: "sort.network-monitor"))
    }

    func allowsDownloads(_ policy: DownloadPolicy) -> Bool {
        switch policy {
        case .never:
            return false
        case .wifiAndMobile:
            return isConnected
        case .wifiOnly:
            return isConnected && !isExpensive
        }
    }
}

/// Cards play muted, so the app mixes with your music; full-screen video switches to playback.
enum AudioSession {
    static func useAmbient() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient)
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    static func usePlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }
}

@MainActor
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func bump() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6)
    }

    static func done() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
