---
name: understand
description: Deep-review the project in the current working directory and produce (1) a 2–3 sentence plain-English summary of what it does, (2) a summary of what's still on the backlog, and (3) a prioritized recommendation order — then persist the findings to long-term memory so future sessions start with the project's context already loaded. Use when the user runs `/understand`, or asks to "understand this project/codebase", "get up to speed on this repo", "review where this project is at", or "what's left to do here".
---

# /understand — deep project review → on-screen briefing → durable memory

Get genuinely up to speed on the project in the current working directory, tell the user the three things that matter (what it does, what's left, what to do first), and write the context to long-term memory so the next session doesn't start cold.

The deliverable is twofold: a **screen briefing** for the human right now, and a **memory entry** for future Claude sessions. Both come from the same review.

## Operating rules

- **Inspect tests, never run them.** Read the test setup and infer coverage and health from it. Do not execute the suite (or any build/run command with side effects) as part of this review.
- **Read-only review.** `/understand` does not modify project code, install dependencies, or open PRs. The only thing it writes is the memory entry (see step 3).
- **Synthesize, don't dump.** The user wants conclusions, not file listings. Use sub-agents to fan out so the raw output stays out of the main thread.

## Step 1 — Deep review

Build a real mental model of the project. Work in this order.

### 1a. Orient

Read the high-signal files first:

- `README*`, `CLAUDE.md`/`AGENTS.md`, `CONTRIBUTING*`, and any `docs/`, `design/`, `spec*`, `*-design.md`, `*-spec.md` files.
- The package/build manifest(s): `package.json`, `pyproject.toml`/`setup.py`, `Cargo.toml`, `go.mod`, `pom.xml`/`build.gradle`, `Gemfile`, `*.csproj`, etc. Note language, runtime, frameworks, scripts, and dependencies.
- `git log --oneline -30` and `git status -sb` — the recent commits reveal the project's trajectory and current phase; uncommitted work reveals what's in flight.

### 1b. Map the architecture

- Survey the source tree. Identify entry points, the main modules/packages, and how they connect.
- Identify the layers/components and the data flow between them.
- **For anything beyond a small repo, dispatch parallel `Explore` (or `general-purpose`) sub-agents** to map subsystems concurrently — e.g. one per top-level source directory — and have each return a tight summary. Keep file dumps in the sub-agents; only conclusions come back.

### 1c. Assess the backlog

Gather "what's left" from the most reliable signals first, and reconcile them:

1. **Explicit plan/work files** — `tasks/`, `TODO.md`, `ROADMAP.md`, `BACKLOG.md`, `CHANGELOG.md`, GitHub issue templates, or design docs with phase/milestone checklists. Count unchecked boxes; note which phases are done vs pending. These are the strongest signal.
2. **Design-vs-implementation gap** — if there's a spec/design doc, which of its components/phases exist in code and which don't? Stubs, mocks "to be replaced", and `NotImplemented`/`TODO`-bodied functions count as backlog.
3. **In-code markers** — grep for `TODO`, `FIXME`, `XXX`, `HACK`, `@deprecated`. Summarize themes and count; do not paste them all.
4. **Test health (inspect only)** — read test files/config: what's covered, what's conspicuously untested, and any `skip`/`xfail`/`.only`/commented-out tests. Do **not** run the suite.
5. **Open issues / PRs** — if `gh` is available and the repo has a GitHub remote, skim `gh issue list` and `gh pr list` for declared work. Best-effort; skip silently if unavailable.

### 1d. Form a priority judgment

Order the backlog into a recommended sequence using: blocking dependencies first → correctness/security risk → the project's own stated next phase → high impact-to-effort → polish. This ordering is your judgment as a reviewer; make it and own it.

## Step 2 — Present the on-screen briefing

Print exactly these three sections to the user, concise and skimmable:

```
## <Project name>

**What it does** — <2–3 sentences in plain language: the problem it solves and how,
including the one distinction that makes it itself. No filler.>

**Backlog** — what's still outstanding
- <grouped, deduplicated items reconciled across the signals in 1c>
- <note done-vs-pending phases if the project is phase-structured>
- <call out the design↔implementation gaps and any inspected test gaps>

**Recommended priority order**
1. <highest-priority item> — <one line: why first / what it unblocks>
2. <next> — <why>
3. <next> — <why>
   …
```

Keep it tight. If the project is large, lead each section with the headline and keep supporting detail to a few bullets.

## Step 3 — Persist to long-term memory

Write the durable context so the next session starts warm. Behavior: **write it, then report what was written** (the user has pre-approved automatic writes; everything here is reversible via the vault's git history).

**Resolve the memory directory** the way the harness does: it's the auto-memory directory whose `MEMORY.md` index you were given at session start. Resolve from `autoMemoryDirectory` in `~/.claude/settings.json` (expand a leading `~`), falling back to `~/claude-memory`. _(In a cloud session memory is injected read-only rather than written to a vault; if no writable memory directory resolves, skip the write and say so in the report instead of failing.)_

**Dedup first.** Scan `MEMORY.md` and existing files for an entry already covering this project. If one exists, **update it in place** rather than creating a duplicate; if it's now wrong, correct it.

**Write one `project` memory file** named `project-<repo-slug>.md` (slug = the repo/dir name, kebab-cased), in the established format:

```markdown
---
name: project-<repo-slug>
description: <one-line: what this project is — used for recall relevance>
metadata:
  type: project
---

<2–3 sentences on what the project does and its current state/phase.>

**Backlog (as of <YYYY-MM-DD>):** <the reconciled outstanding work, condensed.>

**Recommended priority order:** <the ranked next steps from step 1d.>

**Pointers:** <repo path; the load-bearing design/spec/tasks files to read first — link, don't duplicate them.>
```

Then capture only what the **repo doesn't already record on its own**. Skip facts derivable from code, git history, or `CLAUDE.md` — those re-read fine next time. What's worth saving is the *synthesis*: the current-state assessment, the backlog reconciliation, and the priority judgment. Convert any relative dates to absolute (today's date is in session context). Link related memories with `[[name]]` where natural.

**Update the `MEMORY.md` index:** add (or refresh) a one-line pointer under an "Active Projects" section (create the section if absent):

```
- [<Project name>](project-<repo-slug>.md) — <short hook>
```

One line only — never put memory body content in `MEMORY.md`.

## Step 4 — Report

Close with a one-line confirmation of what landed in memory, e.g.:
`Saved project context to memory: project-<repo-slug>.md (+ MEMORY.md index).`
If memory was skipped (no writable vault, e.g. cloud), say so plainly.

## Principles

- **Conclusions over inventory.** The human gets judgment (what, what's-left, what-first), not a directory tree.
- **Faithful backlog.** Reconcile the signals; don't invent work that no source implies, and don't silently drop work a source declares.
- **Own the priority call.** A ranked recommendation is the point — make it, with a one-line reason each.
- **Memory is for the non-obvious.** Save the synthesis (state, backlog, priorities), not what the code already says. Point at the design docs; don't recopy them.
- **Non-destructive.** Inspect, don't run; the only write is the memory entry.

## Distribution / maintenance (for the skill author)

This skill ships in the `kev` plugin of `proton-pidgeon/claude-skills` (marketplace `kevdunn`). It reaches other hosts on `/plugin marketplace update kevdunn` (+ restart) — plugin code is intentionally **not** auto-pulled by the SessionStart sync hook. The *memory entries this skill produces*, however, live in the `~/claude-memory` vault and **are** auto-synced by that hook on session start/end. See `[[claude-sync-architecture]]`.
