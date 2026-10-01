import Foundation
import Photos

/// A snapshot of the library, built off the main thread.
/// PHAsset and PHAssetCollection are immutable and safe to hand between threads.
struct ScanResult: @unchecked Sendable {
    var queue: [PHAsset]
    var albums: [PHAssetCollection]
    var trashAssets: [PHAsset]
    /// The Sorted album ID the scan was given.
    var inputSortedAlbumID: String?
    /// True when that album no longer exists.
    var sortedAlbumMissing: Bool
    /// With no Sorted album on record, an existing album called "Sorted" (for example after a reinstall).
    var sortedAlbumCandidateID: String?
}

enum LibraryScanner {
    /// Builds the sorting queue: every photo and video that isn't in an album
    /// and hasn't been kept or trashed, ordered by date taken.
    static func scan(
        newestFirst: Bool,
        excluded: Set<String>,
        trashIDs: [String],
        sortedAlbumID: String?
    ) -> ScanResult {
        var filed = Set<String>()
        var albums: [PHAssetCollection] = []
        var sortedAlbumFound = false
        var candidateID: String?

        // Anything in a user album (regular, synced from a computer, or imported) counts as filed.
        // This includes albums inside folders.
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        collections.enumerateObjects { collection, _, _ in
            let subtype = collection.assetCollectionSubtype
            if subtype == .albumCloudShared { return }

            let contents = PHAsset.fetchAssets(in: collection, options: nil)
            contents.enumerateObjects { asset, _, _ in
                filed.insert(asset.localIdentifier)
            }

            // Only regular albums can be edited, so only they go in the sidebar.
            guard subtype == .albumRegular else { return }
            let id = collection.localIdentifier
            if let sortedAlbumID {
                if id == sortedAlbumID {
                    sortedAlbumFound = true
                    return
                }
            } else if candidateID == nil, collection.localizedTitle == AppSettings.sortedAlbumTitle {
                candidateID = id
                return
            }
            if collection.canPerform(.addContent) {
                albums.append(collection)
            }
        }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: !newestFirst)]
        // Only your own library: items synced from a computer can't be deleted or filed.
        options.includeAssetSourceTypes = [.typeUserLibrary]

        let all = PHAsset.fetchAssets(with: options)
        var queue: [PHAsset] = []
        queue.reserveCapacity(all.count)
        all.enumerateObjects { asset, _, _ in
            let id = asset.localIdentifier
            if !filed.contains(id) && !excluded.contains(id) {
                queue.append(asset)
            }
        }

        var trashAssets: [PHAsset] = []
        if !trashIDs.isEmpty {
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: trashIDs, options: nil)
            var byID: [String: PHAsset] = [:]
            fetched.enumerateObjects { asset, _, _ in
                byID[asset.localIdentifier] = asset
            }
            trashAssets = trashIDs.compactMap { byID[$0] }
        }

        return ScanResult(
            queue: queue,
            albums: albums,
            trashAssets: trashAssets,
            inputSortedAlbumID: sortedAlbumID,
            sortedAlbumMissing: sortedAlbumID != nil && !sortedAlbumFound,
            sortedAlbumCandidateID: candidateID
        )
    }
}
