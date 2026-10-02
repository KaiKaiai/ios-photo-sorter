# Sort: development

How Sort is built, tested and shipped. There is no Mac: GitHub's cloud Macs compile, sign and upload everything.

## Branches

| Branch | Purpose |
|---|---|
| `dev` | Where all work happens. Every push runs the **Build check**. |
| `main` | The release branch. **Every push to `main` that changes the app uploads a build to TestFlight.** |

The flow is: work on `dev` → the build check goes green → bring `main` up to `dev` → the build lands in TestFlight → tap **Update** on the phone.

## Workflows

### Build check (`.github/workflows/build-check.yml`)
- **Runs:** on pushes to `dev` that touch `Sort/`, `Support/`, `project.yml` or the workflow itself; on pull requests; or by hand.
- **Does:** installs XcodeGen, generates `Sort.xcodeproj` from `project.yml`, and compiles a Release build for iPhone **without signing**. It needs no Apple account.
- **Output:** the full log is kept as the `build-log` artifact on the run.

### TestFlight (`.github/workflows/testflight.yml`)
- **Runs:** on pushes to `main` that touch app code or the workflow; by hand (Actions → TestFlight → Run workflow); and at 21:17 UTC on the 1st of every second month, so an installed build never reaches TestFlight's 90-day expiry.
- **Does:**
  1. Checks the four secrets are set, and fails with their names if not.
  2. Picks a build number (see [Versioning](#versioning)).
  3. Generates the project and archives it **unsigned**.
  4. Exports with `-allowProvisioningUpdates` and the App Store Connect API key, so **Apple signs the app in its cloud** with a managed distribution certificate. No certificates or profiles live in the repo or pile up on the account.
  5. Uploads to App Store Connect for **internal testing only**.
  6. Deletes the key from the runner.
- **Output:** `archive.log` and `export.log` are kept as the `testflight-logs` artifact.

## Deploying

When the owner asks for a deploy:

```sh
git fetch origin
git push origin origin/dev:main
```

This fast-forwards `main` to `dev`, which starts the TestFlight workflow. When it's green, Apple takes 5–15 minutes to process the build. Then tap **Update** in the TestFlight app.

- A push to `main` that only changes docs doesn't start an upload. Use **Run workflow** if you need one anyway.
- If `main` ever has commits that `dev` doesn't, merge `main` into `dev` first.
- Agents deploy this way because the Claude GitHub app can't press Run workflow, and Claude's cloud sessions can't push tags.

## Secrets

Set under GitHub → Settings → Secrets and variables → Actions → **Repository secrets**:

| Secret | Where it comes from |
|---|---|
| `APPLE_TEAM_ID` | developer.apple.com → Account → Membership details (also shown next to your name) |
| `ASC_KEY_ID` | App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys: the key's ID |
| `ASC_ISSUER_ID` | Same page, above the key list |
| `ASC_KEY_P8` | The downloaded `AuthKey_XXXX.p8` file, pasted whole, including the BEGIN and END lines |

- The API key needs **Admin** access, because only Admin keys may use Apple's cloud signing. That makes it powerful, so keep it only in GitHub secrets, never in the repo or a chat.
- **Optional hardening:** move the secrets into a GitHub Environment named `testflight` with yourself as a required reviewer. Every upload then waits for your approval.

## Versioning

TestFlight shows builds as **version (build)**, for example **1.0 (31)**.

| Number | Set by | Changes when |
|---|---|---|
| Version (`1.0`) | `MARKETING_VERSION` in `project.yml` | Only when the owner asks for a new release name |
| Build (`31`) | The TestFlight workflow: **run number × 10 + attempt** | Every TestFlight run |

Run #3 gives build 31, and re-running it after a failure gives 32. Apple requires every upload to have a higher build number than the last, and this guarantees it. Gaps are fine. Older builds stay installable from TestFlight.

## Project configuration

- `project.yml` is the XcodeGen spec: one iOS app target, iOS 17.0, iPhone only, bundle ID `com.kai.sort`, Swift 5, `Support/Info.plist`, and the privacy manifest as a resource.
- `Sort.xcodeproj` is generated on the build machine and ignored by git. Never commit it.
- New Swift files anywhere under `Sort/` are picked up automatically.
- App Store Connect: the app record is **"Sort – kai"**, SKU `sort`, and the internal TestFlight group is **"Me"**.

## Testing

There's no simulator and no automated UI tests, so every change is checked in two stages:

1. **The build check** must be green on `dev`. Re-read your diff before pushing, because each failed cloud build costs about 10 minutes.
2. **On the phone,** after a deploy, run a short test list for the change. It should cover:
   - the main path,
   - declining the iOS prompt (nothing should change, and no error should appear),
   - an empty library or empty album,
   - light and dark mode,
   - the largest Dynamic Type size.

## Common build failures

| Error | Cause and fix |
|---|---|
| `unable to type-check this expression in reasonable time` | A view `body` with a long modifier chain or inline ternaries. Split it into computed properties or `some View` helper functions, and move string logic into named properties. See `AlbumsView`. |
| `Missing repository secrets: …` | A secret is missing or misnamed. Add it under Repository secrets, with the exact name. |
| Export fails with a signing or permission error | The API key isn't **Admin**, or the bundle ID `com.kai.sort` isn't registered under Identifiers. |
| Upload rejected for a duplicate build number | Only possible if the run numbering was reset. Run the workflow again to get a higher number. |
| Build check doesn't run on a new branch | GitHub doesn't apply path filters on a branch's first push. The next push runs it, or start it by hand. |

## Apple account setup (done once)

1. Enrol in the Apple Developer Program.
2. Register the explicit App ID `com.kai.sort` with no capabilities.
3. Create the App Store Connect app "Sort – kai" (English (Australia), SKU `sort`).
4. Create a Team API key with **Admin** access, and download the `.p8` file.
5. Add the four repository secrets.
6. In TestFlight → Internal Testing, create the group "Me", add yourself, and turn on automatic distribution.
7. Install TestFlight on the iPhone, signed in with the same Apple Account, and accept the invite email once.
