import SwiftUI
import Photos

/// One undoable step in the current session.
enum SortAction {
    case trashed(PHAsset)
    case kept(PHAsset)
    case filed(PHAsset, albumID: String)
}

/// A tiny mutable box for passing values out of Photos change blocks.
final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// The app's single source of truth: the sorting queue, albums, Trash and undo history.
/// Every change to the library goes through Apple's Photos framework, so the Photos app
/// sees it straight away.
@MainActor
final class LibraryStore: NSObject, ObservableObject {
    @Published private(set) var authorization: PHAuthorizationStatus
    @Published private(set) var queue: [PHAsset] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var albums: [PHAssetCollection] = []
    @Published private(set) var trashAssets: [PHAsset] = []
    @Published private(set) var undoStack: [SortAction] = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var libraryVersion = 0
    @Published var alertMessage: String?
    @Published private var state: PersistedState

    private let stateFile: StateFile
    private var isObserving = false
    private var saveTask: Task<Void, Never>?
    private var sortedAlbumChain: Task<Void, Never>?

    // Background scans read the whole library, which takes a moment. A scan is only used if
    // nothing changed while it ran, so it can never undo something you just did.
    private var mutationCount = 0
    private var lastMutationAt = Date.distantPast
    private var pendingWrites = 0
    private var reloadAfterWrites = false
    private var resetPositionOnNextApply = false
    private var scanTask: Task<Void, Never>?
    private var rescanNeeded = false
    private var reloadTask: Task<Void, Never>?

    override init() {
        let file = StateFile()
        stateFile = file
        state = file.load()
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        super.init()
        if authorization == .authorized {
            startObserving()
            Task { await reload() }
        }
    }

    // MARK: - Reading

    var isAuthorized: Bool { authorization == .authorized }
    var remainingCount: Int { queue.count }
    var keptCount: Int { state.kept.count }
    var canUndo: Bool { !undoStack.isEmpty }
    /// Left and right loop round the unsorted items, so browsing works whenever there's more than one.
    var canBrowse: Bool { queue.count > 1 }

    var currentAsset: PHAsset? {
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
    }

    /// The card waiting behind the current one: the next item, looping round at the end.
    var nextAsset: PHAsset? {
        guard queue.count > 1, queue.indices.contains(currentIndex) else { return nil }
        return queue[(currentIndex + 1) % queue.count]
    }

    /// The card parked off-screen to the left. With only two items it would be the same
    /// as the next one, so it's left out.
    var previousAsset: PHAsset? {
        guard queue.count > 2, queue.indices.contains(currentIndex) else { return nil }
        return queue[(currentIndex - 1 + queue.count) % queue.count]
    }

    /// Cards to keep on screen: the previous one (parked, so going back is instant),
    /// the next one (waiting behind) and the current one on top.
    var cardStack: [PHAsset] {
        [previousAsset, nextAsset, currentAsset].compactMap { $0 }
    }

    // MARK: - Access

    func requestAccess() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorization = status
        if isAuthorized {
            startObserving()
            await reload()
        }
    }

    func refreshAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status != authorization else { return }
        authorization = status
        if isAuthorized {
            startObserving()
            Task { await reload() }
        }
    }

    private func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        PHPhotoLibrary.shared().register(self)
    }

    // MARK: - Loading

    /// Re-reads the library after a short pause, and not while you're mid-swipe.
    func scheduleReload(after delay: TimeInterval = 1.0) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            let idle = Date().timeIntervalSince(self.lastMutationAt)
            if idle < 1.5 {
                self.scheduleReload(after: 1.5 - idle + 0.1)
                return
            }
            await self.reload()
        }
    }

    /// Re-reads the library. Only one scan runs at a time; asking again while one is
    /// running queues exactly one more.
    func reload(resetPosition: Bool = false) async {
        guard isAuthorized else { return }
        if resetPosition {
            resetPositionOnNextApply = true
        }
        if let running = scanTask {
            rescanNeeded = true
            await running.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.rescanNeeded = false
                await self.scanOnce()
            } while self.rescanNeeded
            self.scanTask = nil
        }
        scanTask = task
        await task.value
    }

    private func scanOnce() async {
        let startedAt = mutationCount
        let newestFirst = AppSettings.newestFirst
        let excluded = state.kept.union(state.trash)
        let trashIDs = state.trash
        let sortedID = state.sortedAlbumID

        let result = await Task.detached(priority: .userInitiated) {
            LibraryScanner.scan(
                newestFirst: newestFirst,
                excluded: excluded,
                trashIDs: trashIDs,
                sortedAlbumID: sortedID
            )
        }.value

        if pendingWrites > 0 {
            // A change to Photos is still on its way; look again once it has landed.
            reloadAfterWrites = true
            return
        }
        if startedAt != mutationCount {
            // You did something while the scan ran; the app's own state is right, so look again later.
            scheduleReload()
            return
        }
        libraryVersion += 1
        applyAlbums(result)
        applyQueue(result)
        hasLoaded = true
    }

    private func applyAlbums(_ result: ScanResult) {
        if result.inputSortedAlbumID == state.sortedAlbumID {
            if result.sortedAlbumMissing {
                state.sortedAlbumID = nil
                scheduleSave()
            } else if state.sortedAlbumID == nil, let candidate = result.sortedAlbumCandidateID {
                state.sortedAlbumID = candidate
                scheduleSave()
            }
        }
        let sortedID = state.sortedAlbumID
        let fresh = result.albums.filter { $0.localIdentifier != sortedID }

        var freshByID: [String: PHAssetCollection] = [:]
        for album in fresh {
            freshByID[album.localIdentifier] = album
        }
        // Keep the order the session started with, so the sidebar doesn't jump under your thumb.
        // Albums that are new since then go to the top.
        let knownIDs = Set(albums.map { $0.localIdentifier })
        let added = sortedByRecency(fresh.filter { !knownIDs.contains($0.localIdentifier) })
        let existing = albums.compactMap { freshByID[$0.localIdentifier] }
        albums = added + existing
    }

    private func applyQueue(_ result: ScanResult) {
        let currentID = currentAsset?.localIdentifier
        queue = result.queue
        trashAssets = result.trashAssets

        let liveTrash = result.trashAssets.map { $0.localIdentifier }
        if liveTrash != state.trash {
            state.trash = liveTrash
            scheduleSave()
        }

        if resetPositionOnNextApply {
            resetPositionOnNextApply = false
            currentIndex = 0
        } else if let currentID, let index = queue.firstIndex(where: { $0.localIdentifier == currentID }) {
            currentIndex = index
        } else if currentIndex >= queue.count {
            currentIndex = 0
        }
    }

    private func sortedByRecency(_ list: [PHAssetCollection]) -> [PHAssetCollection] {
        let lastUsed = state.albumLastUsed
        return list.sorted { a, b in
            switch (lastUsed[a.localIdentifier], lastUsed[b.localIdentifier]) {
            case let (dateA?, dateB?):
                return dateA > dateB
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                let titleA = a.localizedTitle ?? ""
                let titleB = b.localizedTitle ?? ""
                return titleA.localizedStandardCompare(titleB) == .orderedAscending
            }
        }
    }

    /// Called when you press Start: albums you used most recently move to the top.
    func beginSession() {
        albums = sortedByRecency(albums)
        if !hasLoaded {
            Task { await reload() }
        }
    }

    // MARK: - Browsing

    func showNext() {
        guard queue.count > 1 else { return }
        currentIndex = (currentIndex + 1) % queue.count
    }

    func showPrevious() {
        guard queue.count > 1 else { return }
        currentIndex = (currentIndex - 1 + queue.count) % queue.count
    }

    // MARK: - Decisions
    // Each takes the exact item you swiped, and does nothing if it has already left the queue.

    func trash(_ asset: PHAsset) {
        guard removeFromQueue(asset) else { return }
        state.trash.append(asset.localIdentifier)
        trashAssets.append(asset)
        undoStack.append(.trashed(asset))
        scheduleSave()
    }

    func keep(_ asset: PHAsset) {
        guard removeFromQueue(asset) else { return }
        state.kept.insert(asset.localIdentifier)
        undoStack.append(.kept(asset))
        scheduleSave()
        if AppSettings.useSortedAlbum {
            addToSortedAlbum([asset])
        }
    }

    func file(_ asset: PHAsset, into album: PHAssetCollection) {
        guard removeFromQueue(asset) else { return }
        let albumID = album.localIdentifier
        state.albumLastUsed[albumID] = Date()
        undoStack.append(.filed(asset, albumID: albumID))
        scheduleSave()

        let applied = Box(false)
        startWrite({
            guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
            request.addAssets([asset] as NSArray)
            applied.value = true
        }, completion: { [weak self] error in
            guard let self else { return }
            if let error {
                self.filingFailed(asset, albumID: albumID, reason: error.localizedDescription)
            } else if !applied.value {
                self.filingFailed(asset, albumID: albumID, reason: "That album can't be changed.")
            }
        })
    }

    private func filingFailed(_ asset: PHAsset, albumID: String, reason: String) {
        let id = asset.localIdentifier
        undoStack.removeAll { action in
            if case .filed(let filedAsset, let filedAlbum) = action {
                return filedAsset.localIdentifier == id && filedAlbum == albumID
            }
            return false
        }
        reinsert(asset)
        alertMessage = "Couldn't add that item to the album. \(reason)"
    }

    // MARK: - Undo

    func undo() {
        guard let action = undoStack.popLast() else { return }
        switch action {
        case .trashed(let asset):
            let id = asset.localIdentifier
            state.trash.removeAll { $0 == id }
            trashAssets.removeAll { $0.localIdentifier == id }
            reinsert(asset)

        case .kept(let asset):
            state.kept.remove(asset.localIdentifier)
            reinsert(asset)
            // It may be in "Sorted", even if the toggle was switched on after you kept it.
            removeFromSortedAlbum(asset)

        case .filed(let asset, let albumID):
            reinsert(asset)
            if let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject {
                startWrite {
                    PHAssetCollectionChangeRequest(for: album)?.removeAssets([asset] as NSArray)
                }
            }
        }
        scheduleSave()
    }

    // MARK: - Trash

    /// Takes an item back out of the Trash and shows it again.
    func rescue(_ asset: PHAsset) {
        let id = asset.localIdentifier
        guard state.trash.contains(id) else { return }
        state.trash.removeAll { $0 == id }
        trashAssets.removeAll { $0.localIdentifier == id }
        undoStack.removeAll { action in
            if case .trashed(let trashed) = action {
                return trashed.localIdentifier == id
            }
            return false
        }
        reinsert(asset)
        scheduleSave()
    }

    /// Deletes everything in the Trash with one iOS prompt. Returns false if nothing was deleted.
    @discardableResult
    func emptyTrash() async -> Bool {
        guard !trashAssets.isEmpty else { return true }
        let assets = trashAssets.filter { $0.canPerform(.delete) }
        guard !assets.isEmpty else {
            alertMessage = "iOS won't let Sort delete these items. You can delete them in the Photos app."
            return false
        }
        do {
            try await write {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
        } catch {
            if !Self.isUserCancel(error) {
                alertMessage = "Couldn't delete. \(error.localizedDescription)"
            }
            return false
        }
        let ids = Set(assets.map { $0.localIdentifier })
        state.trash.removeAll { ids.contains($0) }
        trashAssets.removeAll { ids.contains($0.localIdentifier) }
        // Deleted items can't come back through undo; Recently Deleted in Photos is the safety net.
        undoStack.removeAll()
        scheduleSave()
        return true
    }

    // MARK: - Albums

    /// Creates an album and puts it at the top of the sidebar.
    func createAlbum(named rawName: String) async -> PHAssetCollection? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let createdID = Box<String?>(nil)
        do {
            try await write {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                createdID.value = request.placeholderForCreatedAssetCollection.localIdentifier
            }
        } catch {
            alertMessage = "Couldn't create the album. \(error.localizedDescription)"
            return nil
        }
        guard let id = createdID.value,
              let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        state.albumLastUsed[id] = Date()
        albums.removeAll { $0.localIdentifier == id }
        albums.insert(album, at: 0)
        scheduleSave()
        return album
    }

    func rename(_ album: PHAssetCollection, to rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != album.localizedTitle else { return }
        do {
            try await write {
                PHAssetCollectionChangeRequest(for: album)?.title = name
            }
        } catch {
            alertMessage = "Couldn't rename the album. \(error.localizedDescription)"
            return
        }
        let id = album.localIdentifier
        if let fresh = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject,
           let index = albums.firstIndex(where: { $0.localIdentifier == id }) {
            albums[index] = fresh
        }
    }

    /// Uses Apple's own album delete: the album goes, its photos and videos stay in the library
    /// and come back to be sorted.
    func deleteAlbum(_ album: PHAssetCollection) async {
        do {
            try await write {
                PHAssetCollectionChangeRequest.deleteAssetCollections([album] as NSArray)
            }
        } catch {
            if !Self.isUserCancel(error) {
                alertMessage = "Couldn't delete the album. \(error.localizedDescription)"
            }
            return
        }
        let id = album.localIdentifier
        albums.removeAll { $0.localIdentifier == id }
        state.albumLastUsed[id] = nil
        undoStack.removeAll { action in
            if case .filed(_, let albumID) = action {
                return albumID == id
            }
            return false
        }
        scheduleSave()
        await reload()
    }

    // MARK: - Sorted album

    /// Called when the Sorted toggle is switched on and you agree to add earlier keeps.
    func addKeptItemsToSortedAlbum() {
        let ids = Array(state.kept)
        guard !ids.isEmpty else { return }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        addToSortedAlbum(assets)
    }

    private func addToSortedAlbum(_ assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        enqueueSortedAlbumWork { store in
            guard let album = await store.sortedAlbum(createIfNeeded: true) else { return }
            try? await PHPhotoLibrary.shared().performChanges { @Sendable in
                PHAssetCollectionChangeRequest(for: album)?.addAssets(assets as NSArray)
            }
        }
    }

    private func removeFromSortedAlbum(_ asset: PHAsset) {
        guard state.sortedAlbumID != nil else { return }
        enqueueSortedAlbumWork { store in
            guard let album = await store.sortedAlbum(createIfNeeded: false) else { return }
            try? await PHPhotoLibrary.shared().performChanges { @Sendable in
                PHAssetCollectionChangeRequest(for: album)?.removeAssets([asset] as NSArray)
            }
        }
    }

    /// Sorted-album changes run one after another, so the album is only ever created once.
    /// The pending count covers the wait, so a scan can't catch them half done.
    private func enqueueSortedAlbumWork(_ work: @escaping @MainActor (LibraryStore) async -> Void) {
        pendingWrites += 1
        let previous = sortedAlbumChain
        sortedAlbumChain = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await work(self)
            self.finishWrite()
        }
    }

    private func sortedAlbum(createIfNeeded: Bool) async -> PHAssetCollection? {
        if let id = state.sortedAlbumID,
           let existing = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
            return existing
        }

        // Reuse an album that's already called "Sorted".
        var match: PHAssetCollection?
        let regular = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        regular.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == AppSettings.sortedAlbumTitle {
                match = collection
                stop.pointee = true
            }
        }
        if let match {
            adoptSortedAlbum(match.localIdentifier)
            return match
        }

        guard createIfNeeded else { return nil }
        let createdID = Box<String?>(nil)
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
                    withTitle: AppSettings.sortedAlbumTitle
                )
                createdID.value = request.placeholderForCreatedAssetCollection.localIdentifier
            }
        } catch {
            return nil
        }
        guard let id = createdID.value else { return nil }
        adoptSortedAlbum(id)
        return PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
    }

    private func adoptSortedAlbum(_ id: String) {
        guard state.sortedAlbumID != id else { return }
        state.sortedAlbumID = id
        albums.removeAll { $0.localIdentifier == id }
        scheduleSave()
    }

    // MARK: - Settings actions

    /// Brings every kept item that isn't in an album back into the queue.
    func resetKeptMemory() async {
        state.kept.removeAll()
        undoStack.removeAll { action in
            if case .kept = action { return true }
            return false
        }
        noteMutation()
        scheduleSave()
        await reload()
    }

    // MARK: - Writing to Photos

    /// A change to the Photos library that the caller waits for.
    private func write(_ changes: @escaping @Sendable () -> Void) async throws {
        pendingWrites += 1
        defer { finishWrite() }
        try await PHPhotoLibrary.shared().performChanges(changes)
    }

    /// A change to the Photos library that runs in the background.
    private func startWrite(
        _ changes: @escaping @Sendable () -> Void,
        completion: (@MainActor (Error?) -> Void)? = nil
    ) {
        pendingWrites += 1
        Task {
            var failure: Error?
            do {
                try await PHPhotoLibrary.shared().performChanges(changes)
            } catch {
                failure = error
            }
            self.finishWrite()
            completion?(failure)
        }
    }

    private func finishWrite() {
        pendingWrites -= 1
        noteMutation()
        if pendingWrites == 0 && reloadAfterWrites {
            reloadAfterWrites = false
            scheduleReload(after: 0.3)
        }
    }

    private func noteMutation() {
        mutationCount += 1
        lastMutationAt = Date()
    }

    /// True when you tapped "Don't Allow" on an iOS prompt.
    private static func isUserCancel(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == PHPhotosError.errorDomain && nsError.code == PHPhotosError.Code.userCancelled.rawValue {
            return true
        }
        // Older iOS versions reported a declined prompt as a generic Cocoa error.
        return nsError.domain == NSCocoaErrorDomain && nsError.code == -1
    }

    // MARK: - Queue helpers

    @discardableResult
    private func removeFromQueue(_ asset: PHAsset) -> Bool {
        guard let index = queue.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) else {
            return false
        }
        noteMutation()
        queue.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        }
        if currentIndex >= queue.count {
            // Past the end, loop round to the start: that's the card that was waiting behind.
            currentIndex = 0
        }
        return true
    }

    /// Puts an item back where it belongs by date and shows it.
    private func reinsert(_ asset: PHAsset) {
        noteMutation()
        if let existing = queue.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
            currentIndex = existing
            return
        }
        let newestFirst = AppSettings.newestFirst
        let date = asset.creationDate ?? .distantPast
        let index = queue.firstIndex { other in
            let otherDate = other.creationDate ?? .distantPast
            return newestFirst ? otherDate < date : otherDate > date
        } ?? queue.count
        queue.insert(asset, at: index)
        currentIndex = index
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = state
        let file = stateFile
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            file.save(snapshot)
        }
    }

    func saveNow() {
        saveTask?.cancel()
        stateFile.save(state)
    }
}

extension LibraryStore: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            self?.scheduleReload()
        }
    }
}
