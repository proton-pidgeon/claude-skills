---
name: commit
description: Commit, push, and (when needed) merge the current repo's work in one step — inspect state, stage changes, write a message from the diff, push with upstream set, and on a feature branch open a PR and merge it into the default branch. Use when the user runs `/commit`, or asks to "commit and push", "commit this", "ship it", "push my changes", "land this", "open a PR for this", or "merge this branch". Local CLI/Desktop only — it runs git and, for merges, the `gh` CLI.
---

# /commit — commit, push, and merge whatever is staged or pending

Take the current repository from "I have changes" to "they're landed", doing only as
much as the situation needs. The deliverable: the user's work is committed with a clean
message, pushed to the remote, and — when on a feature branch — merged into the default
branch with the branch cleaned up.

Argument: `$ARGUMENTS` is an optional commit message / intent. If present, use it as the
commit subject (and honor intent words like "no push", "draft pr", "squash"). If empty,
generate the message from the diff.

## Operating rules

- **Never invent work.** Commit what's actually changed. If there's nothing to commit and
  nothing unpushed/unmerged, say so and stop — don't create empty commits.
- **Read before you write.** Always inspect state first; let it decide the path. Don't push
  or merge blindly.
- **Honor the harness git rules** in the current session: append the session's
  `Co-Authored-By:` trailer to the commit message (it's specified per-session and names the
  active model — do not hardcode a model here), and use the session's PR-body footer for any
  PR you open. If no trailer is specified, append `Co-Authored-By: Claude <noreply@anthropic.com>`.
- **Be honest about outcomes.** If a push is rejected, a merge conflicts, or CI is red,
  report it with the real output instead of papering over it.

## Procedure

### 1. Inspect state (one batched read)

Run these together and read the result before doing anything:

```bash
git rev-parse --is-inside-work-tree && \
git status --short --branch && \
git diff --stat && \
git diff --cached --stat
```

Also determine:
- **Current branch:** `git branch --show-current`
- **Default branch:** `git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@'` — if empty, fall back to whichever of `main`/`master` exists on the remote.
- **Remote present?** `git remote` (no remote → commit only, tell the user there's nowhere to push).
- **Ahead/behind upstream**, from the `status --branch` line.

Decide the path:
- **On the default branch** → commit + push directly (the everyday solo-repo flow).
- **On a feature branch** → commit + push + open a PR + merge it into the default branch, then clean up. (See §4.)

### 2. Stage

If nothing is staged, stage all tracked + new files with `git add -A`. If the user already
staged a deliberate subset (staged set non-empty AND unstaged changes remain), respect their
selection and commit only what's staged — mention that you did so.

Glance at the diff for anything that shouldn't be committed (secrets, large binaries, stray
debug files, `.env`). If you spot something risky, pause and flag it rather than committing it.

### 3. Commit

- **Message:** if `$ARGUMENTS` carries a message, use it. Otherwise write a concise subject
  line (≤ ~70 chars, imperative mood) from the diff, plus a short body of bullet points when
  the change is non-trivial. Match the repo's existing commit style (skim `git log --oneline -10`).
- Append the session's `Co-Authored-By:` trailer (see Operating rules).
- Commit. Do **not** use `--no-verify` unless the user asked — let hooks run.

### 4. Push and (if needed) merge

**Push** the current branch, setting upstream if it has none:

```bash
git push -u origin "$(git branch --show-current)"
```

If the push is rejected as non-fast-forward, do **not** force-push. Pull/rebase
(`git pull --rebase`) only if that's clearly safe, otherwise report and ask.

**On the default branch:** you're done after the push. Report the commit and that it's pushed.

**On a feature branch**, land it (unless `$ARGUMENTS` says "no merge" / "draft" / "pr only"):

1. Open or update a PR with `gh pr create` (title from the commit subject, body summarizing
   the change + the session's PR-body footer). If a PR already exists for the branch, reuse it.
2. Merge it: `gh pr merge --squash --delete-branch` (squash is the sensible default; honor a
   "merge"/"rebase" intent in `$ARGUMENTS`). If branch protection requires it, the merge may
   wait on checks — if so, prefer `gh pr merge --squash --delete-branch --auto` so it lands
   when CI passes, and tell the user it's set to auto-merge.
3. After a completed merge, switch back to the default branch and fast-forward:
   `git checkout <default> && git pull --ff-only`.

If `gh` isn't installed or authenticated, fall back to a local merge into the default branch
only when that's clearly safe and the user expects it; otherwise stop after the push and tell
the user the PR step needs `gh`.

### 5. Report

End with a short, factual summary: the commit hash + subject, whether it was pushed, and —
for a feature branch — the PR URL and whether it was merged (or is set to auto-merge / awaiting
checks). Mention anything you deliberately skipped (e.g. "left 2 unstaged files alone").

## Notes

- This skill is the user's codified workflow, so committing directly to the default branch is
  intended here — it deliberately overrides the usual "branch first" default.
- Merging and pushing are outward-facing. The smart policy above means a single `/commit` on a
  feature branch will land code on the default branch; that's the chosen behavior. If the user
  wants to stop short, they pass "pr only" / "no merge".
