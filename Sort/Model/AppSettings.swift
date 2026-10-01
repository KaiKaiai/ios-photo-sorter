import Foundation

/// When Sort may fetch originals from iCloud.
enum DownloadPolicy: String, CaseIterable, Identifiable {
    case wifiOnly
    case wifiAndMobile
    case never

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wifiOnly: return "Wi-Fi only"
        case .wifiAndMobile: return "Wi-Fi and mobile data"
        case .never: return "Never"
        }
    }
}

enum SettingsKey {
    static let useSortedAlbum = "useSortedAlbum"
    static let downloadPolicy = "downloadPolicy"
    static let newestFirst = "newestFirst"
}

/// Reads the same values the Settings screen writes through @AppStorage,
/// with the same defaults.
enum AppSettings {
    static let sortedAlbumTitle = "Sorted"

    static var useSortedAlbum: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.useSortedAlbum)
    }

    static var newestFirst: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.newestFirst) as? Bool ?? true
    }

    static var downloadPolicy: DownloadPolicy {
        guard let raw = UserDefaults.standard.string(forKey: SettingsKey.downloadPolicy),
              let policy = DownloadPolicy(rawValue: raw) else {
            return .wifiOnly
        }
        return policy
    }
}
