# Sort: architecture

How the code is put together. For the rules agents must follow, see [`AGENTS.md`](../AGENTS.md). For the look, see [`DESIGN.md`](DESIGN.md).

## Overview

Sort is a single-target SwiftUI app with no dependencies beyond Apple's frameworks. One observable store owns all library state, and the views read from it and call it.

```
SortApp
 └─ RootView ── picks a screen from the Photos permission
     ├─ PermissionView        (ask / limited / denied)
     └─ HomeView              (NavigationStack)
         ├─ AlbumsView        (pushed)
         ├─ SortView          (full-screen cover)
         │   ├─ CardView ×3   (previous, next, current)
         │   ├─ AlbumSidebar
         │   ├─ TrashTray
         │   └─ FullScreenViewer
         ├─ TrashReviewView   (sheet)
         └─ SettingsView      (sheet)

LibraryStore (@MainActor ObservableObject, injected as an environment object)
 ├─ LibraryScanner    builds the queue and album list off the main thread
 ├─ StateFile         saves PersistedState as JSON
 └─ PHPhotoLibrary    every read and write of the Photos library
```

## Files

| File | Role |
|---|---|
| `App/SortApp.swift` | App entry, `RootView` (permission routing, save on background) and `PermissionView` |
| `Model/AppSettings.swift` | `SettingsKey` (UserDefaults keys), `DownloadPolicy`, and `AppSettings` for reading settings outside views |
| `Model/PersistedState.swift` | `PersistedState` (what Sort remembers) and `StateFile` (atomic JSON save and load) |
| `Services/LibraryStore.swift` | The single source of truth: the queue, the current index, albums, Trash, undo, and every Photos write |
| `Services/LibraryScanner.swift` | A pure function that turns the Photos library into a `ScanResult` |
| `Services/MediaLoaders.swift` | `AssetImageLoader`, the video loader and the Live Photo loader, with iCloud handling |
| `Services/Device.swift` | Network monitoring for the iCloud setting, the audio session, and `Haptics` |
| `Views/HomeView.swift` | Counts, Trash and Albums buttons, Start, Settings |
| `Views/SortView.swift` | The sorting screen: the gesture, swipe decisions, card animation and commits, album dialogs |
| `Views/CardView.swift` | One card: still, looping muted video, Live Photo on hold, cloud badge |
| `Views/AlbumSidebar.swift` | The album list while sorting, and `AlbumTile` |
| `Views/AlbumsView.swift` | The Albums screen: grid, CRUD, selection mode, drag to select, batch delete |
| `Views/TrashTray.swift` | The tray on the sorting screen and `TrashReviewView` |
| `Views/FullScreenViewer.swift` | The view-only zoom and playback screen |
| `Views/SettingsView.swift` | The settings form |
| `Views/Components.swift` | UIKit bridges (video layer, Live Photo view, zoomable scroll view), badges, and `libraryErrorAlert` |

## LibraryStore

`LibraryStore` is `@MainActor` and an `ObservableObject`. Views only read its `@Published private(set)` state and call its methods.

| State | Meaning |
|---|---|
| `authorization` | The Photos permission |
| `queue`, `currentIndex` | Items left to sort, and which one is on screen |
| `albums` | Regular albums for the sidebar and the Albums screen, without "Sorted" |
| `trashAssets` | Items waiting to be deleted |
| `undoStack` | `SortAction`s since launch: `.trashed`, `.kept`, `.filed(albumID:)` |
| `libraryVersion` | Bumped when the library changes, so covers and counts refresh |
| `alertMessage` | An error to show, in plain English |

### The sorting queue

`LibraryScanner.scan` runs off the main thread and returns a `ScanResult`:

1. It goes through every user album (`.album`, any subtype, including those in folders) and records their assets as **filed**. Shared albums are skipped and don't count as filed.
2. **Regular** albums that can take new content go into the album list. The "Sorted" album is set aside, and an existing album called "Sorted" is adopted after a reinstall.
3. It fetches every image and video from the **user's own library** (`includeAssetSourceTypes = .typeUserLibrary`, so items synced from a computer are excluded), sorted by `creationDate`. Hidden assets are excluded by Photos' defaults.
4. The queue is every asset that isn't filed, kept or in the Trash.

### Decisions

| Method | Effect |
|---|---|
| `trash(_:)` | Removes from the queue, adds to the Trash (persisted), pushes undo |
| `keep(_:)` | Removes from the queue, records as kept (persisted), and adds to "Sorted" if that setting is on |
| `file(_:into:)` | Removes from the queue, adds to the album in the background, records the album's last use. On failure the item goes back into the queue with an error. |
| `undo()` | Reverses the last action, including removing the item from the album or from "Sorted" |
| `rescue(_:)` | Takes an item out of the Trash and back into the queue |
| `emptyTrash()` | Deletes every Trash item in **one** change request, so there's one iOS prompt. Clears undo, since deleted items can't come back. |
| `createAlbum(named:)`, `rename(_:to:)` | Album create and rename |
| `deleteAlbums(_:)` | Deletes several albums in **one** change request. Photos stay in the library and come back to the queue on reload. Undo entries for those albums are dropped. |
| `resetKeptMemory()` | Clears the kept set and reloads |

Every decision takes the exact asset the user swiped, and does nothing if that asset has already left the queue. That makes double-commits from fast gestures harmless.

### Writes and background rescans

All Photos writes go through `write(_:)` (the caller waits) or `startWrite(_:completion:)` (runs in the background). Both count `pendingWrites` and record a mutation.

Photos change notifications (`photoLibraryDidChange`) schedule a rescan. A rescan's result is applied **only if nothing changed while it ran**. That way a scan started before a swipe can never bring back an item you just sorted. If writes are pending, the reload waits until they finish.

"Sorted" album writes are chained one after another (`enqueueSortedAlbumWork`), so the album is only created once.

### Persistence

`PersistedState` is saved as `sort-state.json` in Application Support, with a short debounce, and immediately when the app goes to the background. It holds:

- `kept`: IDs of items kept without filing.
- `trash`: IDs waiting in the Trash, oldest first.
- `albumLastUsed`: dates, for the sidebar order.
- `sortedAlbumID`: the "Sorted" album, once it exists.

Settings are `@AppStorage` values under the `SettingsKey` keys. `AppSettings` reads them outside views with the same defaults.

## The sorting screen

- **One gesture on the card area** handles tap (full screen), press and hold (Live Photo) and swipes, so it keeps working as cards change underneath. A swipe's direction is whichever axis moved most. It commits past 100 pt or on a fast flick (predicted end), and otherwise springs back.
- **Pending commits:** a swipe animates the card off first, and the store change runs when the animation ends. If you start another action first, the pending change runs straight away, so fast swipes never get lost.
- **Card stack:** only the previous, next and current cards are kept on screen. Only the current card may download from iCloud or play video.
- **Sidebar order** is fixed when a session starts (`beginSession`), so it doesn't move while you sort. New albums go to the top.

## Media loading

- `AssetImageLoader` requests stills from `PHImageManager`. With iCloud allowed (per `DownloadPolicy` and the current network), it fetches originals with progress. Otherwise it serves the on-phone copy and reports `originalInCloud`, which shows the cloud badge.
- The video loader gives cards a muted, looping player and full screen a player with sound. Players paused by iOS restart when the app comes back.
- The Live Photo loader only fetches the moving part once you press and hold.
- **Audio:** cards use an ambient session, so your music keeps playing. Full screen switches to playback and restores the session on close.

## Albums screen

- The grid is `LazyVGrid` with adaptive columns, sorted A–Z. Each tile loads its key photo and its count, and refreshes when `libraryVersion` changes.
- **Selection** is a set of `localIdentifier`s. Albums that disappear (for example, deleted in Photos) are dropped from it automatically.
- **Drag to select:**
  - Each tile reports its frame in the grid's coordinate space through a preference key.
  - A simultaneous `DragGesture`, active only in selection mode, decides on its first movement. Sideways means select; up or down hands the drag to the scroll view.
  - While selecting, the range between the anchor tile and the tile under the finger is added to (or removed from) the selection as it was before the drag, and scrolling is disabled.

## Privacy

- `NSPhotoLibraryUsageDescription` explains the need for Full Access.
- `PrivacyInfo.xcprivacy` declares no tracking and no collected data.
- `ITSAppUsesNonExemptEncryption` is `false`, so TestFlight doesn't ask about export compliance.
