---
name: ship-ios
description: Repair Xcode Cloud code-signing after adding a capability, app extension, or App Group to an existing app — the failure where the archive builds but exportArchive dies with "Automatic signing cannot update bundle identifier" / "No profiles found", because enabling a capability invalidated every managed profile. Walks the known recipe (register the appex bundle id + capability via the App Store Connect API, do the portal-only App Group assignment to BOTH App IDs, create manual IOS_APP_STORE profiles, verify the entitlement actually landed in profileContent, re-run the build via the API). Use when the user runs `/ship-ios`, or asks "my Xcode Cloud build won't sign", "exportArchive fails after I added an extension/App Group", or "fix the provisioning profiles for this app". macOS; needs App Store Connect API credentials + portal access.
---

# /ship-ios — repair Xcode Cloud signing after a capability/extension change

Adding an app extension + App Group (or any capability) to an existing Xcode-Cloud-built app
breaks signing in a specific, repairable way. This skill drives the recipe that worked on
`[[project-fovea]]` (2026-06-04; same class as the ellisX TestFlight 347 failure), captured
in `[[asc-appex-signing-gotcha]]`. The deliverable: a re-run build that signs and exports.

## The failure (confirm this is what you're seeing)

1. Enabling a capability on an App ID **invalidates every existing managed profile** for it
   (the "iOS Team … Profile" entries go INVALID).
2. The archive **builds fine** — only `exportArchive` dies, with *"Automatic signing cannot
   update bundle identifier `<appex-id>`"* and *"No profiles for `<appex-id>` were found."*
3. So the signature of this bug is: **build green, export red, profiles invalid after a
   capability/target change.** If the build itself is failing, that's a different problem —
   don't apply this recipe.

## What the API can and cannot do (the core trap)

The **public App Store Connect API canNOT**: create App Group identifiers, assign a group to
an App ID, or even *see* Xcode-managed profiles (`/v1/profiles` lists only manual ones —
"deleted 0" is normal). **Those steps are portal-UI-only.** The API *can* register bundle
ids, toggle capabilities, create *manual* profiles, and trigger builds. The recipe
interleaves both — and the **only ground truth the API gives you is the profile content**,
so verify there.

## Operating rules

- **Credentials required.** Needs an ASC API key (issuer id + key id + `.p8`) with the right
  role, and the user must have **portal (developer.apple.com) access** for the UI-only steps.
  If creds aren't available, stop and say what's needed.
- **Hand off the portal steps explicitly.** Don't pretend the API can do the App Group
  assignment. Tell the user exactly what to click, then verify their work via the API.
- **Verify, don't trust.** A profile created before the portal assignment silently lacks the
  group. Decode `profileContent` and grep for the group id before re-running the build.
- **Single-line commands only.**

## Procedure

### 1. Confirm the failure class
Read the failed Xcode Cloud build log: archive succeeded, `exportArchive` failed with the
bundle-identifier / no-profiles message, managed profiles INVALID. If that's not the shape,
stop — this recipe won't help.

### 2. Register the appex bundle id + capability (API-able)
- `POST /v1/bundleIds` for the appex bundle id (if not already registered).
- `POST /v1/bundleIdCapabilities` enabling `APP_GROUPS` on it.

### 3. App Group → both App IDs (PORTAL UI — hand off)
Direct the user to developer.apple.com: create the App Group identifier (if new), then
**assign it to BOTH App IDs — the main app AND the appex.** The appex assignment is the one
that's easy to miss. Ask them to confirm both are checked; verify in the next step, don't
trust.

### 4. Create manual distribution profiles (API-able)
- `POST /v1/profiles` for `IOS_APP_STORE` profiles for the main app and the appex, using the
  team **DISTRIBUTION** certificate. Xcode Cloud picks up manual profiles.

### 5. Verify the entitlement actually landed (ground truth)
For each created profile, base64-decode the returned `profileContent` and grep the embedded
Entitlements plist for the App Group id. **If the group is missing**, the profile was created
before the portal assignment took effect — **delete and recreate it**, then re-verify. This
is the step that catches the silent failure.

### 6. Re-run the build (API-able)
`POST /v1/ciBuildRuns` with the workflow id to kick a fresh run — **no empty commit needed.**
Then watch the run and confirm export now succeeds.

## Report

State which steps the API handled, which the user did in the portal, the result of the
`profileContent` grep (group present in each profile), and the re-run build status. If export
still fails, report the new log message — a *different* error after this repair means a
different cause, not a reason to loop the same recipe.

## Principles

- **Signing failures surface one layer from their cause.** The export error names the appex;
  the real fix is the group assignment two steps upstream.
- **The API is half the toolkit.** Group creation/assignment is portal-only — interleave,
  don't fight it.
- **profileContent is the only truth.** Grep the decoded entitlements before re-running; a
  profile can look created and still lack the group.

## Distribution / maintenance (for the skill author)

Ships in the `kev` plugin of `proton-pidgeon/claude-skills` (marketplace `kevdunn`); reaches
other hosts on `/plugin marketplace update kevdunn` (+ restart). Encodes `[[asc-appex-signing-gotcha]]`
— update both together if the recipe changes. See `[[claude-sync-architecture]]`.
