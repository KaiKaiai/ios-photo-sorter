# Sort: guide for coding agents

Sort is a personal iPhone app for clearing out a photo library. Each photo or video is deleted, kept or filed into one album. It edits the Photos library directly through Apple's Photos framework, works fully offline, and ships only through TestFlight to its owner.

Read this file and [`docs/DESIGN.md`](docs/DESIGN.md) before changing anything. Follow both. If a request conflicts with them, say so instead of quietly breaking the rule.

## Hard rules

- **Offline and private.** No servers, accounts, analytics, crash reporters, ads or tracking. The only network use allowed is Apple fetching the owner's own iCloud originals, and only as the iCloud setting allows.
- **No third-party dependencies.** Use Apple frameworks only (SwiftUI, Photos, PhotosUI, AVFoundation, AVKit, UIKit, Network). Don't add Swift packages, CocoaPods or vendored code.
- **Never lose photos silently.** Deletes go to the in-app Trash first, and only "Delete N" removes them, behind iOS's own prompt. Deleting an album never deletes its photos. Any new destructive action needs a confirmation and must say what happens to the photos.
- **Never commit secrets.** That means `.p8` keys, certificates, provisioning profiles or Apple IDs. Signing happens in Apple's cloud via the repository secrets `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8`.
- **Never commit `Sort.xcodeproj`.** XcodeGen generates it from `project.yml` on the build machine. Configure the build in `project.yml`.
- **iPhone only, portrait only, iOS 17 or later.** Don't add iPad, landscape or Mac targets.

## Building and shipping

There is no Mac. All builds run on GitHub's cloud Macs, so there's no simulator, and each fix costs one build of about 5–10 minutes. Write code carefully and get it right the first time.

### Branches

| Branch | Purpose |
|---|---|
| `dev` | Where all work happens. Push changes here, or to a feature branch merged into `dev`. |
| `main` | Release only. **Every push to `main` that changes the app uploads a build to TestFlight**, so it lands on the owner's phone. |

| Workflow | Runs | Does |
|---|---|---|
| `.github/workflows/build-check.yml` | On every push to `dev` that touches app code, on pull requests, or by hand | An unsigned compile. This is the check every change must pass. |
| `.github/workflows/testflight.yml` | On every push to `main` that touches app code, by hand (Actions → TestFlight → Run workflow), and on the 1st of every second month | Archives the app, has Apple sign it in the cloud, and uploads it to TestFlight |

- The build check must be green on `dev` before you call any change done. When it fails, read the log, fix the cause and push again. Don't disable or weaken the check.
- **Never push to `main` unless the owner asks for a deploy.** To deploy:
  1. Make sure the build check is green on `dev`.
  2. Fast-forward `main` to `dev`: `git fetch origin && git push origin origin/dev:main`.
  3. Watch the TestFlight run until it's green, then tell the owner to tap **Update** in TestFlight.

  This is the only way an agent can deploy: the Claude GitHub app can't press Run workflow, and Claude's cloud sessions can't push tags.
- If `main` has commits that `dev` doesn't, merge `main` into `dev` first, so the fast-forward works.
- Changes to `.github/workflows/` touch the job that holds the owner's Apple API key. Keep them minimal, never print or send secrets anywhere, and point them out to the owner.
- The build number comes from the workflow's run number. Change `MARKETING_VERSION` in `project.yml` only for a release the owner asks for.
- New Swift files under `Sort/` are picked up automatically. There's no project file to edit.

## Project layout

```
Sort/App        App entry (SortApp), RootView and the permission screens
Sort/Model      AppSettings (UserDefaults keys) and PersistedState (the small JSON state file)
Sort/Services   LibraryStore, LibraryScanner, MediaLoaders, Device (network, audio, haptics)
Sort/Views      One file per screen or major component
Support         Info.plist and PrivacyInfo.xcprivacy
project.yml     The XcodeGen spec: targets, settings, deployment target
```

## Architecture

- **`LibraryStore` is the single source of truth.** It's an `@MainActor ObservableObject`, injected with `.environmentObject`. It owns the queue, albums, Trash, undo history and persisted state. Views read its `@Published private(set)` properties and call its methods. Views never change library state themselves.
- **Every Photos write goes through `LibraryStore`.** Use `write(_:)` when the caller waits, or `startWrite(_:completion:)` for writes that run in the background. These track pending writes, so a background rescan can never undo a change in flight. Don't call `PHPhotoLibrary.shared().performChanges` anywhere else.
- **Batch iOS prompts.** iOS asks before deleting assets or albums. Collect the targets and make one change request, so the owner sees one prompt per action, not one per item. `emptyTrash()` and `deleteAlbums(_:)` follow this pattern.
- **Errors are shown, not swallowed.** Set `library.alertMessage` with a plain-English message plus `error.localizedDescription`. Each screen shows it with `.libraryErrorAlert(isEnabled:)`, enabled only on the screen that's on top. Treat a declined iOS prompt (`isUserCancel`) as a quiet cancel, not an error.
- **Identify assets and albums by `localIdentifier`.** Don't rely on `PHAsset` or `PHAssetCollection` object identity, because fetches return new objects.
- **Load media with the existing loaders** in `MediaLoaders.swift` (`AssetImageLoader` and friends). Pass `allowNetwork` from the iCloud setting, never `true` unconditionally.
- **Small state only.** Persist only what Photos can't tell us (kept IDs, Trash IDs, album last-used dates) via `PersistedState`. Settings live in `AppSettings` keys with `@AppStorage`.

## Code style

Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/), and match the surrounding code.

- Swift 5 language mode with modern concurrency: `async`/`await` and `@MainActor` for UI and store code. Don't use `DispatchQueue.main.async` in new code, and don't use Combine pipelines where `async` will do.
- SwiftUI first. Use UIKit only through `UIViewRepresentable` when SwiftUI can't do the job (zooming, Live Photo playback, the video layer).
- One primary type per file, named after the file. Keep private helper views in the same file, marked `private`.
- Use `private` by default and `private(set)` for published state. Mark types `final` unless they're meant to be subclassed.
- Use `// MARK: -` sections in longer files, in the order: state, `body`, subviews, actions.
- Give every type and every non-obvious function a one-line `///` doc comment. Comments explain *why*, in plain English. Don't narrate what the code obviously does.
- **Keep view bodies small.** A long modifier chain (several `.alert`s or `.confirmationDialog`s) or inline ternaries that build strings can fail with "unable to type-check this expression in reasonable time", and that only shows up in a cloud build. Split `body` into computed properties or `some View` helper functions. Move string and colour logic into named properties. See `AlbumsView` for the pattern.
- No force unwraps (`!`) or `try!` outside of genuinely impossible cases. Use `guard let` and return early.
- No magic numbers scattered through views. Use the sizes in `docs/DESIGN.md`. Name a constant when a value is reused.
- Write user-facing text in plain, friendly sentence case ("Delete 3 albums?", not "DELETE ALBUMS"). Pluralise correctly ("1 item" / "3 items"), and format numbers with `.formatted()` or `Text(_, format:)`.
- Add accessibility to every control: an `accessibilityLabel` on any button that's only an icon, and `.isSelected` and `.isButton` traits where relevant. Use Dynamic Type text styles, not fixed point sizes, for body text.

## Making a change

1. Read the code you're touching, plus `LibraryStore` if the change involves library state.
2. Keep each change focused. Don't reformat or refactor unrelated code in the same commit.
3. Re-read your diff for compile errors before pushing. A failed cloud build costs about 10 minutes.
4. Write a commit message with a short imperative subject ("Add an Albums screen for managing albums in bulk"), then a body saying what changed for the user and why.
5. Push, wait for the **Build check**, and fix it until it's green.
6. Update `README.md` and these docs when behaviour, gestures, screens or the build setup change.

## Checking on a device

There are no automated UI tests. Each feature change needs a short manual test list for the owner to run on the phone after the TestFlight install, covering:

- the main path,
- declining the iOS prompt,
- an empty library or an empty album,
- light and dark mode,
- the largest Dynamic Type size.
