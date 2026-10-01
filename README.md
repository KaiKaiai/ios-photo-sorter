# Sort

A personal iPhone app for clearing out a photo library, one item at a time.

| Gesture | What it does |
| --- | --- |
| Swipe up | Delete (into the Trash tray) |
| Swipe down | Keep |
| Swipe left / right | Next / previous item |
| Tap an album on the right | File it there and move on |
| Tap the item | Full screen (zoom, sound) |
| Press and hold | Play a Live Photo |

It works directly on the Photos library through Apple's Photos framework, so every change shows up in the Photos app straight away. There are no servers, accounts or analytics.

## How it gets built

There's no Mac involved. GitHub's cloud Macs do the work:

- **Build check** runs on every push to `main`. It compiles the app without signing, so it needs no Apple account.
- **TestFlight** runs when started by hand (Actions → TestFlight → Run workflow) and on the 1st of every second month, so a build never hits TestFlight's 90-day expiry. It archives the app unsigned, then signs it with Apple's cloud-managed distribution certificate and uploads it for internal testing.

The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen), so there's no `.xcodeproj` in the repo.

## Secrets the TestFlight workflow needs

Set these under Settings → Secrets and variables → Actions:

| Secret | Where it comes from |
| --- | --- |
| `APPLE_TEAM_ID` | developer.apple.com → Membership details |
| `ASC_KEY_ID` | App Store Connect → Users and Access → Integrations → App Store Connect API |
| `ASC_ISSUER_ID` | Same page, above the key list |
| `ASC_KEY_P8` | The downloaded `.p8` file, pasted whole |

The API key needs **Admin** access: only Admin keys may use Apple's cloud signing.

## Layout

```
Sort/App        App entry and the permission screens
Sort/Model      Settings keys and the small state file
Sort/Services   Library scanning, the store, media loaders, network and haptics
Sort/Views      Home, sorting screen, cards, sidebar, Trash, full screen, Settings
Support         Info.plist and the privacy manifest
```
