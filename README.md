# Sort

A personal iPhone app for clearing out a photo library, one item at a time. For every photo and video that isn't in an album yet, you decide: **delete**, **keep**, or **file it into an album**.

Sort works directly on your Photos library through Apple's Photos framework, so every change shows up in the Photos app straight away. Nothing is copied, nothing leaves the phone, and there are no servers, accounts, analytics or ads.

- iPhone only, portrait, iOS 17 or later
- Delivered through TestFlight, built on GitHub's cloud Macs (no Mac needed)
- Apple frameworks only, no third-party code

## What it can do

### Sorting
- **One item at a time:** shows only photos and videos that aren't in any album and that you haven't kept or deleted yet. Screenshots and Live Photos are included; items in the Hidden album never appear.
- **Ordered by date taken:** newest first, or oldest first in Settings.
- **Swipe to decide:**

  | Gesture | What it does |
  |---|---|
  | Swipe up | Delete: the item goes into the Trash tray, not straight out of your library |
  | Swipe down | Keep: marked done and never shown again |
  | Swipe left / right | Next / previous item, without deciding (loops round at the ends) |
  | Tap an album on the right | File the item into it and move on |
  | Tap the item | Open it full screen |
  | Press and hold | Play a Live Photo |

- **Undo:** steps back through every action since you opened the app, up to the last time you emptied the Trash.
- **Fast swipes never get lost:** a new swipe finishes the previous card's animation instantly.
- **Videos** autoplay muted and loop on the card. **Live Photos** play while you press and hold.
- **Full screen** is view-only. You can pinch or double-tap to zoom photos and Live Photos, and press and hold to play a Live Photo. Videos play with sound. Swipe down or tap × to close.

### Trash
- Deleted items collect in the **Trash tray** along the bottom of the sorting screen, and on the Home screen.
- Tap a thumbnail to **rescue** it back into the queue.
- **Delete N** removes them all with **one** iOS prompt. They then sit in Photos' Recently Deleted for 30 days.
- The Trash is remembered between sessions.

### Albums
- **Sidebar while sorting:** every album as its cover photo, with the most recently used first. Tap **+** to create an album, which also files the current item into it. Long-press an album to rename or delete it.
- **Albums screen** (from Home):
  - Every album as a large cover, A–Z, with its item count.
  - Create with **+**, or tap an album to **Rename**, **Select** or **Delete** it.
  - **Batch delete:** hold an album, or tap **Select**, to enter selection mode. Tap to tick albums, or **drag sideways** across them to select a range, like the Photos app. **Select All** is available, and **Delete N** removes them all behind one iOS prompt.
- **Deleting an album never deletes photos.** Its photos and videos stay in your library and come back to be sorted.
- Only regular albums are listed. Smart albums (Favourites, Screenshots), shared albums, albums synced from a computer, and the "Sorted" album are left alone.

### Settings
| Setting | Options | Default |
|---|---|---|
| Add kept items to a "Sorted" album | On / Off | Off |
| Download originals from iCloud | Wi-Fi only / Wi-Fi and mobile data / Never | Wi-Fi only |
| Order | Newest first / Oldest first | Newest first |

There's also **Reset Kept Memory**, which brings every kept item that isn't in an album back into the queue. See the [user guide](docs/USER_GUIDE.md) for details on each.

### Privacy
- Needs **Full Access** to Photos. With Limited access, it explains how to switch.
- The only network use is Apple fetching your own originals from iCloud, and only as the iCloud setting allows.
- Remembers only what Photos can't tell it (kept and trashed item IDs, album last-used dates), in a small file on the phone.

## Documentation

| Doc | For |
|---|---|
| [User guide](docs/USER_GUIDE.md) | Using the app: every screen, gesture and setting, plus troubleshooting |
| [Architecture](docs/ARCHITECTURE.md) | How the code works: the store, the sorting queue, Photos writes, media loading |
| [Development](docs/DEVELOPMENT.md) | Branches, building, deploying to TestFlight, secrets, versioning, testing |
| [Design guide](docs/DESIGN.md) | The look and feel: colours, type, spacing, motion, patterns |
| [Agent guide](AGENTS.md) | Rules for coding agents (Claude Code loads it through `CLAUDE.md`) |

## Quick start for development

There's no Mac involved. GitHub's cloud Macs do the work:

1. Work on the `dev` branch. Every push runs the **Build check**, an unsigned compile.
2. To ship, bring `main` up to `dev`. Every push to `main` that changes the app uploads a build to **TestFlight**.
3. On the phone, tap **Update** in TestFlight.

The full details, including the four repository secrets the upload needs, are in [Development](docs/DEVELOPMENT.md).

## Layout

```
Sort/App        App entry, root view and the permission screens
Sort/Model      Settings keys and the small state file
Sort/Services   The library store, library scanning, media loaders, network, audio and haptics
Sort/Views      Home, sorting screen, cards, sidebar, Albums, Trash, full screen, Settings
Support         Info.plist and the privacy manifest
docs/           User guide, architecture, development and design docs
project.yml     XcodeGen spec (the Xcode project is generated on the build machine)
```

## Licence

[MIT](LICENSE). You're free to use, change and share the code. To run your own copy, register your own bundle ID and set up your own Apple Developer account and secrets, as described in [Development](docs/DEVELOPMENT.md).
