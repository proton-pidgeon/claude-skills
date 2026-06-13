---
name: portfolio
description: Sweep every repo under ~/code-local and report a portfolio-wide status table — current branch, ahead/behind upstream, uncommitted/untracked changes, last commit, and whether tests exist — then flag the repos that need attention (unpushed, uncommitted, behind/diverged, dirty) and reconcile against the project memory entries. Use when the user runs `/portfolio`, or asks "what's the state of all my projects", "which repos have uncommitted/unpushed work", "sweep my code-local repos", "what needs attention across my projects", or "what have I left in flight". Read-only; it does not commit, pull, or run tests.
---

# /portfolio — status sweep across all ~/code-local repos

`/understand` goes deep on one repo; `/portfolio` goes wide across all of them. With ~20+
projects in flight (see the Active Projects in `MEMORY.md`), the recurring questions are
"what did I leave uncommitted / unpushed?" and "which of these has drifted from what memory
says?" This sweep answers both in one skimmable table plus a short flagged list.

## Operating rules

- **Read-only.** No `commit`/`pull`/`merge`/`checkout`/`reset`, no installs. `git fetch` is
  allowed (read-only — updates remote-tracking refs) but is **opt-in** (it's network-bound
  and slow across many repos): only fetch if the user asks for behind/ahead vs the true
  remote; otherwise report against existing tracking refs and say so.
- **Inspect tests, don't run them.** Test *presence* and rough health from the tree/config —
  never execute a suite.
- **Synthesize, don't dump.** The output is a table + flags, not per-repo file listings.
  Fan out with sub-agents when there are many repos so raw output stays out of the main thread.
- **Single-line commands only.**

## Step 1 — Discover the repos

Enumerate git repos directly under the dev root (default `~/code-local`, honor `$DEV_ROOT`):
list immediate subdirectories containing a `.git`. Keep it to one level deep unless the user
asks to recurse. Note the count up front.

## Step 2 — Gather per-repo state

For each repo collect (cheaply, all local unless fetch was requested):
- **Branch** — `git -C <repo> branch --show-current`.
- **Ahead/behind upstream** — from `git -C <repo> status -sb` / `git rev-list --left-right
  --count @{u}...HEAD` (skip gracefully if no upstream).
- **Working-tree state** — counts of modified / staged / untracked (`git status --porcelain`).
- **Last commit** — date + subject (`git log -1 --format='%cs %s'`).
- **Tests present?** — a `tests/`, `test/`, `__tests__/`, `*_test.*`, `*.test.*`, or a test
  script in the build manifest (presence only).

For a large set, dispatch parallel `Explore`/`general-purpose` sub-agents (a batch of repos
each) returning one tight row per repo. Conclusions come back, not file dumps.

## Step 3 — Reconcile with memory

Cross-reference each repo against its `project-<slug>` entry in `MEMORY.md`:
- Repos with **no** memory entry → candidates for `/understand`.
- Repos whose memory says "clean/merged" but the tree is **dirty or ahead** → drift worth
  flagging (memory is stale or work is unfinished).
- Memory entries whose repo path no longer exists → stale pointer.

## Step 4 — Present the sweep

Lead with a compact table sorted so the repos **needing attention float to the top**:

```
| Repo | Branch | Sync | Dirty | Last commit | Tests |
|------|--------|------|-------|-------------|-------|
| …    | hack   | ↑2   | 3 M   | 2026-06-11 …| yes   |
```

Then a short **Needs attention** list, grouped by kind:
- **Uncommitted work** — dirty trees (modified/untracked) that could be lost.
- **Unpushed** — branches ahead of their remote.
- **Behind / diverged** — only meaningful if `fetch` was run; say if it wasn't.
- **Drift vs memory** — repos contradicting their `project-<slug>` entry.
- **No tests** — flag the notably untested ones (several memory entries already note this).

Keep it tight; the value is the ranked "what to deal with first," not exhaustive detail.

## Step 5 — Offer follow-ups (don't auto-run)

Suggest the obvious next actions and let the user pick: `/commit` on a repo with uncommitted
or unpushed work, `/understand` on a repo missing a memory entry or showing drift. Don't
perform them as part of the sweep — `/portfolio` only reports.

## Principles

- **Wide, not deep.** One row per repo; depth is `/understand`'s job.
- **Surface risk first.** Uncommitted and unpushed work is what actually gets lost — rank it up.
- **Memory is the second source of truth.** Reconcile the tree against what was recorded;
  divergence is itself a finding.
- **Read-only and offline by default.** Fetch only on request; never mutate a working tree.

## Distribution / maintenance (for the skill author)

Ships in the `kev` plugin of `proton-pidgeon/claude-skills` (marketplace `kevdunn`); reaches
other hosts on `/plugin marketplace update kevdunn` (+ restart). Complements `[[skill-understand]]`
(per-repo deep review) and feeds `/commit`. See `[[claude-sync-architecture]]`.
