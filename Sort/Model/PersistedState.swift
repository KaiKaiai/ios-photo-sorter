import Foundation

/// Everything Sort remembers between launches. It lives in a small JSON file
/// in Application Support; the photos themselves never leave the Photos library.
struct PersistedState: Codable, Equatable {
    /// Items you swiped down on (kept without filing).
    var kept: Set<String> = []
    /// Items waiting in the Trash, oldest first.
    var trash: [String] = []
    /// When each album was last used, for the sidebar order.
    var albumLastUsed: [String: Date] = [:]
    /// The "Sorted" album, once it exists.
    var sortedAlbumID: String?
}

final class StateFile: @unchecked Sendable {
    private let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("sort-state.json")
    }

    func load() -> PersistedState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return PersistedState()
        }
        return state
    }

    func save(_ state: PersistedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
