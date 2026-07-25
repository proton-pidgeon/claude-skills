---
name: portfolio
description: Sweep every repo under ~/code-local AND every repo in the user's GitHub account, then report a portfolio-wide status table — current branch, ahead/behind upstream, uncommitted/untracked changes, last commit, and whether tests exist — plus a three-way reconciliation (local ↔ GitHub ↔ project memory) that flags repos needing attention (unpushed, uncommitted, behind/diverged, dirty, on GitHub but not cloned here, local-only with no remote). Use when the user runs `/portfolio`, or asks "what's the state of all my projects", "which repos have uncommitted/unpushed work", "sweep my code-local repos", "check my GitHub repos", "what needs attention across my projects", or "what have I left in flight". Read-only; it does not commit, pull, or run tests.
---

# /portfolio — status sweep across ~/code-local + GitHub

`/understand` goes deep on one repo; `/portfolio` goes wide across all of them. With ~20+
projects in flight (see the Active Projects in `MEMORY.md`), the recurring questions are
"what did I leave uncommitted / unpushed?", "which of these has drifted from what memory
says?", and "what exists on GitHub that isn't on this machine at all?" This sweep answers
all three in one skimmable table plus a short flagged list.

## Operating rules

- **Read-only.** No `commit`/`pull`/`merge`/`checkout`/`reset`, no installs. `git fetch` is
  allowed (read-only — updates remote-tracking refs) but is **opt-in** (it's network-bound
  and slow across many repos): only fetch if the user asks for behind/ahead vs the true
  remote; otherwise report against existing tracking refs and say so.
- **GitHub access is read-only too.** `gh repo list` / `gh api` GETs only — never create,
  archive, or modify anything. If `gh` is missing or unauthenticated, degrade gracefully:
  run the local-only sweep and say the GitHub side was skipped and why.
- **Inspect tests, don't run them.** Test *presence* and rough health from the tree/config —
  never execute a suite.
- **Synthesize, don't dump.** The output is a table + flags, not per-repo file listings.
  Fan out with sub-agents when there are many repos so raw output stays out of the main thread.
- **Single-line commands only.**

## Step 1 — Discover local repos

Enumerate git repos directly under the dev root (default `~/code-local`, honor `$DEV_ROOT`
— `$env:DEV_ROOT` on a native Windows host, where the root resolves under the user profile):
list immediate subdirectories containing a `.git`. Keep it to one level deep unless the user
asks to recurse. Note the count up front.

## Step 2 — Discover GitHub repos

Enumerate the authenticated account's repos in one call:

`gh repo list --limit 300 --json name,nameWithOwner,defaultBranchRef,pushedAt,visibility,isFork,isArchived`

- This lists the account `gh` is logged in as; if the user names other owners/orgs, add a
  `gh repo list <owner> …` per owner.
- Keep `isArchived` repos out of the attention list (they're deliberately parked) but count
  them in the summary line.
- Match GitHub repos to local clones by comparing `nameWithOwner` against each local repo's
  `git -C <repo> remote get-url origin` (normalize `.git` suffix and ssh/https forms) —
  name-vs-dirname matching alone misbreaks on renames and forks.

## Step 3 — Gather per-repo state (local clones)

For each local repo collect (cheaply, all local unless fetch was requested):
- **Branch** — `git -C <repo> branch --show-current`.
- **Ahead/behind upstream** — from `git -C <repo> status -sb` / `git rev-list --left-right
  --count @{u}...HEAD` (skip gracefully if no upstream).
- **Working-tree state** — counts of modified / staged / untracked (`git status --porcelain`).
- **Last commit** — date + subject (`git log -1 --format='%cs %s'`).
- **Tests present?** — a `tests/`, `test/`, `__tests__/`, `*_test.*`, `*.test.*`, or a test
  script in the build manifest (presence only).

For a large set, dispatch parallel `Explore`/`general-purpose` sub-agents (a batch of repos
each) returning one tight row per repo. Conclusions come back, not file dumps.

## Step 4 — Reconcile local ↔ GitHub ↔ memory

Three-way cross-reference; each mismatch is a finding:

**Local vs GitHub:**
- **On GitHub, not cloned here** — a repo in the account with no matching local clone.
  Report it (name, visibility, last-pushed date, fork?) — it may be work-in-flight from
  another host, or a project with no local checkout at all.
- **Local-only, no GitHub remote** — a local repo whose `origin` is missing or points
  elsewhere: nothing backs it up; flag it.
- **Remote moved past the local clone** — GitHub `pushedAt` is *newer* than the local
  clone's last commit date on repos where the tree is clean and not ahead: likely another
  host pushed. This date heuristic needs no fetch; say it's a heuristic. (Exact
  ahead/behind still requires the opt-in fetch.)

**Vs memory** — cross-reference each repo against its `project-<slug>` entry in `MEMORY.md`:
- Repos (local **or** GitHub-only) with **no** memory entry → candidates for `/understand`.
- Repos whose memory says "clean/merged" but the tree is **dirty or ahead** → drift worth
  flagging (memory is stale or work is unfinished).
- Memory entries whose repo path no longer exists locally → stale pointer (unless the memory
  itself says there's no local clone yet).

## Step 5 — Present the sweep

Lead with a compact table of local clones sorted so the repos **needing attention float to
the top**:

```
| Repo | Branch | Sync | Dirty | Last commit | Tests |
|------|--------|------|-------|-------------|-------|
| …    | hack   | ↑2   | 3 M   | 2026-06-11 …| yes   |
```

Then a short **GitHub-only** table (repos with no clone on this host):

```
| Repo (GitHub only) | Visibility | Last pushed | Fork? | Memory entry? |
```

Then a short **Needs attention** list, grouped by kind:
- **Uncommitted work** — dirty trees (modified/untracked) that could be lost.
- **Unpushed** — branches ahead of their remote.
- **Behind / diverged** — only meaningful if `fetch` was run; say if it wasn't.
- **Remote moved on** — clean local clones whose GitHub `pushedAt` is newer (pushed from
  another host; heuristic).
- **Local-only** — repos with no GitHub remote (no backup).
- **Not cloned here** — GitHub repos absent from this host (informational unless memory
  says they should be here).
- **Drift vs memory** — repos contradicting their `project-<slug>` entry.
- **No tests** — flag the notably untested ones (several memory entries already note this).

Keep it tight; the value is the ranked "what to deal with first," not exhaustive detail.

## Step 6 — Offer follow-ups (don't auto-run)

Suggest the obvious next actions and let the user pick: `/commit` on a repo with uncommitted
or unpushed work, `/understand` on a repo missing a memory entry or showing drift, a clone
command for a GitHub-only repo the user wants locally. Don't perform them as part of the
sweep — `/portfolio` only reports.

## Principles

- **Wide, not deep.** One row per repo; depth is `/understand`'s job.
- **Surface risk first.** Uncommitted and unpushed work is what actually gets lost — rank it
  up. Local-only repos are the same risk class (one dead disk from gone).
- **Memory is the second source of truth.** Reconcile the tree against what was recorded;
  divergence is itself a finding.
- **Read-only everywhere.** Local git is offline by default (fetch on request); the GitHub
  side is inherently network-bound but strictly GET — never mutate a working tree or a
  remote repo.

## Distribution / maintenance (for the skill author)

Ships in the `kev` plugin of `proton-pidgeon/claude-skills` (marketplace `kevdunn`); reaches
other hosts on `/plugin marketplace update kevdunn` (+ restart). Complements `[[skill-understand]]`
(per-repo deep review) and feeds `/commit`. See `[[claude-sync-architecture]]`.
