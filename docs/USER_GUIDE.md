# Sort: user guide

Sort helps you clear out your photo library. It shows you, one at a time, every photo and video that isn't in an album yet, and you **delete**, **keep** or **file** each one.

Everything happens in your real Photos library: an album you file into in Sort is the same album in the Photos app, and changes appear there straight away.

## First launch

Sort asks for access to your photos. Choose **Allow Full Access**.

- With **Limited** access, Sort can only see a few items, so it shows a screen explaining how to switch: Settings → Sort → Photos → Full Access.
- If access is off, the same screen offers an **Open Settings** button.

You can change this at any time in the iPhone's Settings app → Privacy & Security → Photos → Sort.

## Home

Home shows:

- **How many items are left to sort.** When nothing's left you'll see "All sorted", and new photos show up here as you take them.
- **The Trash button:** how many items are waiting to be deleted. Tap it to review them.
- **The Albums button:** how many albums you have. Tap it to manage them.
- **Start:** opens the sorting screen.
- **The gear icon** at the top right opens Settings.

## Sorting

The sorting screen has four parts:

- **The top bar:** Home (back), how many items are left, and Undo.
- **The current item** in the middle.
- **Your albums** down the right side.
- **The Trash tray** along the bottom.

### What you'll be shown

Every photo and video that:
- isn't in any album you made (albums in folders count too),
- you haven't kept, and
- isn't in the Trash.

Screenshots and Live Photos are included. Items in Photos' **Hidden** album never appear, and neither do items synced from a computer, which iOS doesn't let apps change.

Items are ordered by **date taken**: newest first by default, or oldest first in Settings.

### Gestures

| Do this | What happens |
|---|---|
| **Swipe up** | Delete. The item drops into the Trash tray. Nothing is removed from your library until you empty the Trash. |
| **Swipe down** | Keep. A green tick appears and the item is marked done, so it won't come back. |
| **Swipe left** | Skip to the next item without deciding. It stays in the queue for next time. |
| **Swipe right** | Go back to the previous item. |
| **Tap an album** in the sidebar | File the item into that album and move on. Each item goes into one album. |
| **Tap the item** | Open it full screen. |
| **Press and hold** | Play a Live Photo. |

- Left and right loop round: after the last item comes the first.
- A swipe that goes at an angle counts as whichever direction it mostly goes.
- You can swipe as fast as you like. Each new swipe finishes the previous card's animation instantly, so nothing gets dropped.
- Every action gives a light haptic tick.

### Videos and Live Photos
- **Videos** play muted on a loop on the card, so they won't interrupt your music.
- **Live Photos** play while you press and hold.

### Full screen
Tap an item to open it full screen. It's view-only, so nothing here can delete or file.
- **Photos and Live Photos:** pinch or double-tap to zoom. Press and hold to play a Live Photo.
- **Videos:** play with sound and a scrubber.
- **To close:** swipe down, or tap ×.

### Undo
**Undo** in the top bar steps back through every action since you opened the app: deletes, keeps and filings. It reaches back as far as the last time you emptied the Trash, because emptied items can't be restored by Sort. They're still in Photos' Recently Deleted for 30 days.

## The Trash

Items you swipe up on wait in the Trash until you choose to delete them. The Trash is remembered when you close the app.

- **While sorting:** the tray along the bottom shows thumbnails. Tap one to **rescue** it back into the queue, or tap **Delete N** to empty it.
- **From Home:** tap the Trash button to see everything in a grid. Tap an item to rescue it, or tap **Delete N Items**.

Deleting shows **one** iOS prompt for the whole pile. Afterwards the items sit in **Recently Deleted** in the Photos app for 30 days, where you can still recover them.

## Albums

### In the sorting sidebar
- Albums are shown as their cover photo with the name underneath, with the ones you used most recently at the top. The order is fixed when you press Start, so it doesn't jump around under your thumb.
- **+** at the top creates a new album, and the current item goes straight into it.
- **Long-press** an album to **Rename** or **Delete Album**.

### The Albums screen
Open it from the **Albums** button on Home. It shows every album as a large cover, A–Z, with how many items each holds.

- **Create:** tap **+** at the top right.
- **Rename, select or delete one album:** tap it and choose from the menu.
- **Delete several at once:**
  1. **Hold** an album, or tap **Select**. Selection mode starts, with that album ticked.
  2. Tap albums to tick or untick them, or **drag sideways** across them to select a whole range, like in the Photos app. Starting a drag on an album that's already ticked unticks the range instead. Dragging up or down still scrolls.
  3. Use **Select All** / **Deselect All** at the top if you need them.
  4. Tap **Delete N** at the bottom and confirm. iOS shows one prompt for all of them.
  5. Tap **Cancel** to leave selection mode.

### What deleting an album does
It deletes the **album only**. The photos and videos in it stay in your library, and because they're no longer in an album, they come back to be sorted.

### Albums Sort doesn't show
Smart albums (Favourites, Screenshots and so on), shared albums, albums synced from a computer, and the "Sorted" album aren't listed, because they can't be filed into or are managed by Sort itself.

## Settings

### Add kept items to a "Sorted" album (default: off)
- When on, items you keep without filing also go into an album called **Sorted** in Photos, so everything you keep sits in exactly one album.
- Anything in Sorted counts as done, so if you reinstall the app it picks up where you left off.
- Turning it on offers to add the items you'd already kept. Turning it off leaves the album as it is.
- The Sorted album is hidden from Sort's album lists, so you can't file into it by accident.

### Download originals from iCloud (default: Wi-Fi only)
If you use iCloud Photos with "Optimise iPhone Storage", the full-quality originals may not be on your phone.
- **Wi-Fi only / Wi-Fi and mobile data:** originals load automatically as you open or play something, like the Photos app. Only what you open or play is downloaded.
- **Never:** you see the copy that's on your phone, with a **cloud badge** when the original isn't there.

### Order (default: newest first)
Sorts by date taken, newest or oldest first. Changing it starts you from the top of the new order.

### Reset Kept Memory
Sort remembers the items you kept on this phone. This button brings every kept item that **isn't in an album** back into the queue, so you can sort them again. It asks you to confirm first.

### Version
Shows the app version and build number, for example **1.0 (31)**.

## Troubleshooting

| Problem | Fix |
|---|---|
| Sort only shows a few items | You've given Limited access. Settings → Privacy & Security → Photos → Sort → Full Access. |
| A photo looks blurry or has a cloud badge | The original is in iCloud. Allow downloads in Settings, or connect to Wi-Fi if it's set to Wi-Fi only. |
| "iOS won't let Sort delete these items" | Some items, such as ones synced from a computer, can only be deleted in the Photos app. |
| I deleted something by mistake | Open the Photos app → Albums → Recently Deleted. Items stay there for 30 days. |
| I kept something by mistake | Use Undo during the same session, or Settings → Reset Kept Memory to bring all kept items back. |
| No update shows in TestFlight | Pull down to refresh in TestFlight. New builds take 5–15 minutes to appear after upload. |
