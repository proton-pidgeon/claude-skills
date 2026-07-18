---
name: ship-ios-setup
description: Take a scaffolded iOS app (XcodeGen `project.yml` + an app extension/widget + App Group) from "code compiles" to "a git push auto-ships to TestFlight" — the FIRST-time setup, not a repair. Does the one-time App Store Connect provisioning (register app + appex bundle ids + App Groups capability via the ASC API, hand off the portal-only App Group assignment to BOTH App IDs + the app-record creation, mint/verify profiles), bakes the App-Store validation requirements into `project.yml` (app icon + CFBundleIconName, orientations + device family, export-compliance), and stands up Xcode Cloud (ci_post_clone that runs xcodegen, automatic signing, the one-time repo-connect) so pushes auto-build to TestFlight. Ships an optional local `ship.sh` fallback with the keychain gotchas baked in. Use when the user runs `/ship-ios-setup`, or asks to "set up TestFlight for this app", "make builds automatic", "I don't want to run a command for every build", "ship this iOS app", or "get this app onto TestFlight" for an app that has NEVER shipped. macOS; needs App Store Connect API credentials + one-time portal/Xcode access. For an app that already shipped and broke signing after a capability change, use `/ship-ios` (the repair) instead.
---

# /ship-ios-setup — first TestFlight + hands-off auto-delivery for an iOS app

Every new iOS app you ship hits the same wall: an XcodeGen `project.yml`, an app extension +
App Group, first-time provisioning, a handful of App-Store validation gates, and wiring up
CI so builds happen on a push instead of a terminal command. This skill does that end to end.
It is the **setup** counterpart to [[ship-ios]] (which **repairs** signing after a capability
change on an already-shipped app). It encodes what `[[project-verba]]`'s first ship
(2026-07-18) paid for live — see also `[[asc-appex-signing-gotcha]]`.

The deliverable: a **`VALID` build on TestFlight** and a **workflow so future pushes ship
themselves**.

## Confirm this is first-ship, not a repair

- **First-ship (this skill):** the app has no App Store Connect record, has never been
  archived/uploaded, no Xcode Cloud workflow. You're standing everything up.
- **Repair (→ `/ship-ios`):** the app already ships, but after adding a capability/appex the
  archive builds and `exportArchive` dies with "cannot update bundle identifier / no profiles."
  That's a different, narrower recipe — don't run this one.

## Operating rules

- **Identifiers are durable account records — confirm before registering.** Match the account
  convention (e.g. `com.k3v.<App>`, appex `com.k3v.<App>.<Ext>`, group `group.com.k3v.<App>`).
  Never register a placeholder reverse-domain you invented.
- **The API is half the toolkit.** Registering bundle ids + capabilities + profiles + reading
  build state is API-able. **Creating/assigning an App Group, creating the app record, and
  connecting Xcode Cloud to the repo are portal/Xcode-UI only** — hand those off explicitly and
  verify via the API; don't pretend the API did them.
- **Prefer Xcode Cloud; it removes the local keychain from the equation.** Local signing on a
  Mac is where the pain lives (see Phase 4). If the user wants hands-off builds, Xcode Cloud is
  the answer and skips all of it.
- **Bake validation gates into `project.yml`** so they never resurface on the next app.
- **Outward-facing.** This registers records on the user's Apple account and distributes a
  build. Confirm scope before the account writes; hand off the human steps clearly.
- **Single-line commands only.**

## Phase 0 — Locate credentials + decide identifiers

- **ASC API key:** `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8` (key id is in the
  filename). The **issuer id** is an account-level UUID, usually already stored for a sibling
  app — check `~/.config/<otherapp>/testflight.env` / that app's fastlane config and reuse it
  (same account = same issuer id). If truly missing, ask the user for it.
- **Team id + distribution cert:** `security find-identity -v -p codesigning` (look for "Apple
  Distribution: <NAME> (<TEAMID>)"). Get the cert's ASC id via `GET /v1/certificates?filter[certificateType]=DISTRIBUTION`.
- **Bundle ids:** propose `com.<acct>.<App>` matching the account's other apps; get the user's
  nod. Fix them in `project.yml` (bundleIdPrefix + PRODUCT_BUNDLE_IDENTIFIER per target), both
  `.entitlements` files (the App Group), and any `AppConfig` constant — all must agree.
- **ASC JWT:** ES256, `{iss: issuer, iat, exp: iat+900, aud: "appstoreconnect-v1"}`, header
  `{kid: keyid, typ: JWT}`, signed with the `.p8`. A tiny `uv run --with pyjwt --with cryptography`
  script against `https://api.appstoreconnect.apple.com` is the cleanest driver.

## Phase 1 — Register on the account (API) + portal handoff

1. **Register bundle ids (API):** `POST /v1/bundleIds` for the app and the appex
   (`attributes: {identifier, name, platform: "IOS", seedId: <team>}`). Check existence first
   (idempotent).
2. **Enable the capability (API):** `POST /v1/bundleIdCapabilities` with
   `capabilityType: "APP_GROUPS"` on **both** bundle ids.
3. **Portal handoff (human — the API cannot do these):**
   - developer.apple.com → Identifiers → **App Groups** → create `group.<...>` .
   - Assign that group to **BOTH** App IDs (the app AND the appex — the appex is the one that's
     easy to miss). Both must point at the same group or the widget can't read the app's data.
   - App Store Connect → Apps → **＋ New App** → select the app bundle id (the app **record**
     must exist before any upload). App name must be unique store-wide; the on-device display
     name comes from `CFBundleDisplayName`, not this.
4. **Verify the assignment took (ground truth):** create one manual `IOS_APP_STORE` profile per
   bundle id (`POST /v1/profiles`, relate the bundle id + the distribution cert), base64-decode
   `profileContent`, and grep for the App Group id. **If the group is missing, the portal step
   didn't take — delete and recreate the profile after fixing it.** (For Xcode-Cloud-only
   delivery you don't strictly need these profiles, but this grep is the cheapest confirmation
   the portal assignment worked; keep them installed for the local fallback.)

## Phase 2 — Make the bundle pass App Store validation (bake into `project.yml`)

These are the gates a first upload trips one at a time — set them all up front:

- **App icon.** An `Assets.xcassets/AppIcon.appiconset` with a 1024×1024 PNG (single
  `size:"1024x1024", idiom:"universal", platform:"ios"` entry → Xcode generates the rest). If
  the app has none, generate one on-brand (a serif letterform on the app's background grade
  works well; Pillow + `/System/Library/Fonts/NewYork.ttf` is a good default). Set
  `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`.
- **`CFBundleIconName`.** **Xcode 16/26 `GENERATE_INFOPLIST_FILE` does NOT reliably inject
  `CFBundleIconName`**, and its absence fails validation. Use an explicit generated Info.plist
  via XcodeGen's `info:` block with `CFBundleIconName: AppIcon` (and `CFBundleDisplayName`,
  `UILaunchScreen: {}`, `UIApplicationSceneManifest`). Gitignore the generated `App/Info.plist`.
- **Orientations + device family.** `UISupportedInterfaceOrientations` with ≥1 value, and
  `TARGETED_DEVICE_FAMILY: "1"` (iPhone-only) so you don't trip the iPad-multitasking rule that
  demands all four orientations. Set the same family on the appex.
- **Export compliance.** `ITSAppUsesNonExemptEncryption: false` for HTTPS-only apps — skips the
  per-build "provide export compliance" prompt.
- **App Group entitlement on BOTH targets** (`.entitlements` files, `CODE_SIGN_ENTITLEMENTS`).
- **Verify locally without signing:** `xcodebuild -project <p>.xcodeproj -scheme <S> -sdk
  iphonesimulator -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
  -derivedDataPath build-rel CODE_SIGNING_ALLOWED=NO build`, then
  `/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" <built>.app/Info.plist` and check the
  120×120 icon (`AppIcon60x60@2x.png`) exists. Green here = the archive will pass these gates.

## Phase 3 — Xcode Cloud (hands-off: push → TestFlight)

1. **Automatic signing.** Set the Release config to `CODE_SIGN_STYLE: Automatic` (+ team) and
   **remove any manual profile specifiers** — Xcode Cloud manages certs/profiles in the cloud,
   and manual specifiers it doesn't hold will fail. (The App Group is registered + assigned, so
   automatic resolves cleanly — the thing that used to break it is fixed.)
2. **`ci_scripts/ci_post_clone.sh`** at the repo root (Xcode Cloud runs it after clone, before
   build) so the cloud has the gitignored, XcodeGen-generated project:
   ```sh
   #!/bin/sh
   set -e
   brew install xcodegen
   cd "$CI_PRIMARY_REPOSITORY_PATH/ios" && xcodegen generate
   ```
   Keep the scheme **shared** (XcodeGen default) so the workflow can select it.
3. **One-time repo connect (human — not fully API-able):** in **Xcode → Integrate → Create
   Workflow** (or App Store Connect → the app → **Xcode Cloud**), grant Apple access to the
   GitHub repo, and create a workflow: **Start Condition** = Branch Changes on `main`,
   **Action** = Archive (iOS), **Post-Action** = TestFlight (Internal Testing). Xcode reads the
   scheme from the local (generated) project to configure it, so run `xcodegen generate` first.
4. From then on, **`git push` to `main` = a TestFlight build** — no local machine involved.
   (Once a workflow exists, a build can also be kicked via `POST /v1/ciBuildRuns` — that's what
   `/ship-ios` uses for re-runs.)

## Phase 4 — Optional local fallback (`ship.sh`) + the keychain gotchas

A one-shot local `xcodegen → archive → exportArchive → altool upload` is handy, but local
signing is where the pain lives. If you write it, encode these (all hit on verba):

- **Must run in a GUI login session.** A detached/automated/SSH shell can't unlock the login
  keychain → `codesign` fails with `errSecInternalComponent` or **hangs** on a suppressed
  auth dialog. Run `ship.sh` from the user's Terminal, not from an agent's shell.
- **A stray CI keychain hijacks codesign.** If the distribution key also lives in a separate
  build keychain (e.g. `ellis-build.keychain`) with a *different* password, codesign may pick
  that copy and hang on a prompt the login password can't satisfy. **Restrict the search list
  to `login.keychain` and restore it on exit:**
  ```sh
  ORIG="$(security list-keychains -d user | tr -d '"' | tr '\n' ' ')"
  trap 'security list-keychains -d user -s $ORIG' EXIT
  security list-keychains -d user -s "$HOME/Library/Keychains/login.keychain-db"
  security unlock-keychain "$HOME/Library/Keychains/login.keychain-db"   # prompts locally
  ```
  Also pass `OTHER_CODE_SIGN_FLAGS="--keychain $HOME/Library/Keychains/login.keychain-db"` to
  the archive. The first codesign may still need a one-time **"Always Allow"** (or a
  `security set-key-partition-list -S apple-tool:,apple:,codesign: -s login.keychain-db`).
- **Upload:** `xcrun altool --upload-app --type ios --file <ipa> --apiKey <KEYID> --apiIssuer <ISSUER>`.
- Never put the login password in a command that's logged; prompt for it locally via
  `security unlock-keychain` (no `-p`).

## Report

State: which steps the API did (bundle ids, capability, profiles, and the `profileContent`
group grep result), which the user did in the portal/Xcode (App Group assignment, app record,
workflow connect), the local validation result (CFBundleIconName + icon present in the Release
build), and — via `GET /v1/builds?filter[app]=<id>&sort=-uploadedDate` — the build's
`processingState` (**`VALID`** = processed and ready for TestFlight). If a validation upload
failed, quote the exact `detail:` and fix that gate (they surface one at a time).

## Principles

- **First-ship vs repair.** This stands things up; `[[ship-ios]]` fixes a broken managed-signing
  re-run. Don't run the repair recipe on an app with no workflow/app-record.
- **The App-Group-on-both-App-IDs is the silent-failure point.** The API can't do it and a
  profile minted before the assignment silently lacks the group — grep `profileContent`.
- **Xcode Cloud is the hands-off answer.** It builds + signs in the cloud, so the local-keychain
  saga never happens. Reach for the local `ship.sh` only as a fallback.
- **Bake the validation gates into `project.yml`,** so the next app inherits them instead of
  re-discovering icon/orientation/compliance failures one upload at a time.
- **Verify with commands, not vibes.** A `-configuration Release` simulator build + a PlistBuddy
  check proves the bundle-side gates before you spend an archive; the `profileContent` grep and
  `processingState=VALID` prove the account side.

## Distribution / maintenance (for the skill author)

Ships in the `kev` plugin of `proton-pidgeon/claude-skills` (marketplace `kevdunn`); reaches
other hosts on `/plugin marketplace update kevdunn` (+ restart) and the fleet auto-updater.
**Bump `plugins/kev/.claude-plugin/plugin.json` `version` on any content change** or `plugin
update` no-ops (`[[claude-skills-version-bump-gotcha]]`). Sibling of `[[ship-ios]]` (repair) —
if the ASC provisioning steps change, update both. Authored 2026-07-18 from `[[project-verba]]`'s
first ship; its exemplar `project.yml`, `ship.sh`, `ci_scripts/ci_post_clone.sh`, and app-icon
generator live in `~/code-local/verba/ios/`. See `[[claude-sync-architecture]]`.
