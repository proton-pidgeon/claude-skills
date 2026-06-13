---
name: fork-hack
description: Set up a new personal hack-fork of an upstream repo to Kev's exact convention — fork to the proton-pidgeon org, clone into ~/code-local, set origin = the fork (fetch+push) and upstream = the original (fetch-only, push DISABLED so you can never accidentally push to upstream), and create/check out the working branch `hack`. Use when the user runs `/fork-hack`, or asks to "fork this repo for hacking", "set up a hack-fork of <repo>", "clone <upstream> as a sandbox fork", or "make a personal fork I can mess with". Local CLI/Desktop only; uses git and the `gh` CLI.
---

# /fork-hack — stand up a personal hack-fork to the house convention

Take an upstream repo and produce a local sandbox fork wired exactly the way Kev's other
forks are (`[[project-n8n]]`, `[[project-whisper]]`, `[[project-yt-dlp]]`,
`[[project-clicky]]`, `[[project-fooocus]]`, `[[project-languagetool]]`, `[[project-penpot]]`):
a fork under `proton-pidgeon`, cloned into `~/code-local/<name>`, with **origin = the fork**
and **upstream = the original, push-disabled**, on a working branch named **`hack`**.

The deliverable is a ready-to-hack checkout where `git push` can only ever reach *your* fork,
never the upstream project.

## The convention (what "done" looks like)

- **Location:** `~/code-local/<name>` (name = the upstream repo name unless the user gives one).
- **`origin`** → `https://github.com/proton-pidgeon/<name>.git` — fetch **and** push (your fork).
- **`upstream`** → the original repo — **fetch-only; push URL set to `DISABLE`** so an
  accidental `git push upstream` fails loudly instead of opening a PR upstream.
- **Branch `hack`** — checked out, tracking the fork; all work happens here, default branch
  left pristine for clean upstream merges.

## Operating rules

- **Never push to upstream.** The whole point of the push-disable is safety; verify it landed.
- **Don't clobber an existing checkout.** If `~/code-local/<name>` already exists, stop and
  report rather than overwriting — the user may already have local work there.
- **`gh` does the fork.** Requires `gh` authenticated as the proton-pidgeon owner. If `gh`
  isn't available, fall back to creating the fork in the GitHub UI and just wire the remotes.
- **Single-line commands only** — no `\` continuations or heredocs.

## Procedure

### 1. Resolve inputs
- **Upstream** — `owner/name` or a URL (from the argument or by asking).
- **Local name** — default to the upstream repo name; honor an override.
- Confirm `~/code-local/<name>` does **not** already exist (`test -d`). If it does, stop.

### 2. Fork and clone
- Fork to the org without auto-cloning, then clone the fork:
  `gh repo fork <owner>/<name> --org proton-pidgeon --clone=false --remote=false`
  then `git clone https://github.com/proton-pidgeon/<name>.git ~/code-local/<name>`.
  (If the fork already exists in the org, `gh repo fork` is a no-op — proceed to clone.)

### 3. Wire the remotes
After cloning, `origin` already points at the fork. Add upstream and disable its push:
- `git -C ~/code-local/<name> remote add upstream https://github.com/<owner>/<name>.git`
- `git -C ~/code-local/<name> remote set-url --push upstream DISABLE`
- `git -C ~/code-local/<name> fetch upstream`

### 4. Create the working branch
- Determine the upstream default branch (`git -C … symbolic-ref --short refs/remotes/origin/HEAD`
  → strip `origin/`; fall back to `main`/`master`).
- `git -C ~/code-local/<name> checkout -b hack` (from the default branch) and push it to the
  fork: `git -C ~/code-local/<name> push -u origin hack`.

### 5. Verify
- `git -C ~/code-local/<name> remote -v` — confirm: `origin` fetch+push → fork; `upstream`
  fetch → original; **`upstream` push → `DISABLE`** (the safety check).
- `git -C ~/code-local/<name> branch --show-current` → `hack`.

## Report

Confirm the checkout path, the remote wiring (call out that upstream push is disabled), and
the current branch. Note that the fork starts with **zero local changes** — it's a sandbox.
Offer to run `/understand` to map the upstream codebase, since memory tends to want a
`project-<name>` entry for each fork.

## Principles

- **Push can only reach your fork.** Verify the `DISABLE` push URL every time — it's the one
  guardrail that makes hacking on someone else's code safe.
- **Default branch stays pristine.** Work on `hack` so upstream merges stay clean.
- **Don't overwrite.** An existing local dir means existing work — stop and ask.

## Distribution / maintenance (for the skill author)

Ships in the `kev` plugin of `proton-pidgeon/claude-skills` (marketplace `kevdunn`); reaches
other hosts on `/plugin marketplace update kevdunn` (+ restart). Pairs naturally with
`[[skill-understand]]` to seed a project memory for the new fork. See `[[claude-sync-architecture]]`.
