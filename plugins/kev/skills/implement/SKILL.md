---
name: implement
description: Autonomously implement a `tasks/`-based backlog (as produced by `/ingest`) by fanning out one worktree-isolated sub-agent per task along the dependency DAG, gating each on a green test/build AND an adversarial Codex review, then merging everything back into the base branch and cleaning up. Use when the user runs `/implement`, or asks to "implement the tasks/backlog", "build out the specs", "work through tasks/ in parallel", or "execute the implementation plan". Local CLI/Desktop only — it creates git worktrees, runs the project's tests, and calls the Codex plugin for review.
---

# /implement — autonomous, worktree-isolated, DAG-parallel implementation

Take a `tasks/` backlog (the output of `/ingest`: `tasks/NN-<slug>.md` files + `tasks/README.md`, each task declaring `Depends on:`, `Relevant specs:`, deliverable checkboxes, and a `Definition of done`) and **build it** — fanning out one sub-agent per task, each in its own git worktree, in dependency order, gating each on a green test/build **and an adversarial Codex review**, then merging the lot back into the base branch and cleaning up.

This skill is the executing half of the `/ingest → /implement` pipeline. `/ingest` writes the contract; `/implement` fulfills it. It runs **fully autonomously** once started: no per-task approval gate. Its safety comes from worktree isolation, the green gate, the adversarial-review gate, quarantine-on-failure, and the fact that nothing reaches the base branch until it passes both gates.

## Operating rules

- **The task files are the contract.** Each `tasks/NN-*.md` plus its `Relevant specs:` is self-sufficient (that's an `/ingest` guarantee). Implement to the spec; do **not** invent scope the task doesn't declare, and do **not** silently drop a declared deliverable.
- **Green or it didn't happen.** A task is "done" only when its `Definition of done` passes — run the real command, don't reason about it. Integrated green (full suite on the merged base) is a separate, stricter gate than per-worktree green.
- **Reviewed or it doesn't merge.** After green, each task's branch faces an adversarial Codex review (Phase 1.5). A high-severity finding blocks the merge exactly as a red test would. On by default; `--no-review` opts out.
- **Isolate, then integrate.** Every task is built in its own worktree on its own branch. Nothing touches the base branch until it has passed green + review, merged cleanly, and left the suite green.
- **Quarantine, don't abort.** One task failing any gate must not sink the run. Quarantine it and press on with everything that doesn't depend on it.
- **Local only.** This skill creates git worktrees, runs the project's test/build, and invokes the Codex plugin. It is not designed for cloud sessions; if `CLAUDE_CODE_REMOTE=true`, say so and stop.
- **Push is backup, not publication.** Feature branches are pushed for off-machine safety and deleted once merged. No PRs are opened (per design) — the deliverable is merged commits on the base branch.

## Phase 0 — Preflight (do all of this before spawning anything)

1. **Refuse cloud.** If `CLAUDE_CODE_REMOTE=true`, stop with a one-line explanation — worktrees + long test runs are a local-only operation.
2. **Locate the backlog.** Find `tasks/` (cwd first; honor a path in `$ARGUMENTS`). If absent, tell the user to run `/ingest` first (or point you at the tasks dir). Read `tasks/README.md` and every `tasks/NN-*.md`.
3. **Build the DAG.** Parse each task's `Depends on:` (and the `Depends on` column in `tasks/README.md`) into a dependency graph. Treat sub-tasks (`04a`, `04b`, …) as nodes under their parent's ordering. **Reject cycles** — if the graph has one, report the cycle and stop; the backlog is malformed.
4. **Confirm a clean, green baseline.**
   - The working tree must be clean (no uncommitted changes) and on a sensible base branch. If dirty, stop and ask the user to commit/stash.
   - Detect the project's test/build command (read `package.json` scripts, `Makefile`, `pyproject.toml`, `justfile`, CI config, or a project skill). If you cannot determine how to verify, **ask** — you cannot gate on green without it.
   - **Run it once on the base.** If the baseline is already red, the default is to **abort**: gating on green is meaningless from a red start. Report which tests fail and stop. **But brownfield repos are often red on `main` for reasons orthogonal to the backlog** (a coverage-gate threshold, pre-existing lint/type drift, an ordering-flaky singleton test). In that case, offer the user one of two paths rather than a dead stop: (a) **fix the red baseline first as its own task** — attribute each failure via `git log -S`/`git show`, repair the *test* to encode the deliberate product change (never relax an assertion to vacuity); or (b) switch to **differential gating** — run tests green with the coverage gate off (e.g. `pytest --no-cov`), and require *zero new* lint/type findings versus a per-branch baseline you capture up front, rather than an absolute-zero bar. Pick this only with the user's nod; note it in the plan so the weaker gate is on the record.
   - Record the base branch name and its HEAD commit — this is the merge target, the review base (`--base`), and the rollback anchor.
5. **Confirm the review gate is usable** (unless `--no-review`). The gate uses the Codex plugin (`openai/codex-plugin-cc`). Check that `/codex:*` commands are available and Codex is authenticated — a quick `/codex:setup` reports readiness. **If Codex is not installed/authed:** tell the user, and ask whether to proceed with `--no-review` (green-gate only) or stop to fix Codex. Never silently skip the review the user asked for.
6. **Plan the waves.** Topologically sort the DAG into waves (a wave = all tasks whose dependencies are already merged). Print the plan: the wave order, which tasks run in parallel, the verify command, and whether the review gate is on. Then proceed (no approval gate — but the plan is on screen so an interrupt is possible).

## Phase 1 — Fan out per wave (worktree-isolated sub-agents)

Process waves in order. Within a wave, fan out **concurrently** — one sub-agent per task, each with `isolation: worktree` (or an explicit `git worktree add ../<repo>-impl-NN impl/NN-slug`). Cap concurrency at roughly CPU-cores − 2; excess tasks queue.

**Branch each wave off the *current* base HEAD, not the frozen Phase-0 baseline.** A wave's worktrees must include everything prior waves already merged, or a task won't see its own merged dependencies. So the base for wave *k* is base-branch HEAD *after* waves 1…*k*−1 merged — not the commit you recorded in Phase 0. Have each sub-agent make `git checkout -B impl/NN <current-base-HEAD>` its **first** step rather than trusting the worktree snapshot, which the harness can cut stale (pre-merge). Also **copy any git-ignored `.env`/secrets into each worktree right after creating it** — `git worktree add` only carries committed files, so a task whose `Definition of done` needs live keys otherwise runs against an empty env and fails silently. For heavy shared deps (torch/whisper/etc.), build one `<repo>/.venv` once and point every worktree agent's commands at its absolute path instead of installing per-worktree.

Each task's sub-agent is given **only** its `tasks/NN-*.md` and the files its `Relevant specs:` point to, and told to:

1. Read the task file + linked specs. The deliverables and `Definition of done` are the checklist.
2. Implement the **Deliverables**, staying within scope (respect `Anti-deliverables`).
3. **Run the `Definition of done` to green.** Iterate until the verify command passes. Tick the `- [ ]` boxes in its own copy of the task file as each is satisfied.
4. Commit incrementally (one logical change per commit, per the task file's "Notes for Claude Code") on `impl/NN-slug`.
5. **Push the branch** (`git push -u origin impl/NN-slug`) as an off-machine backup.
6. Return a structured result: `{ task, status: green|failed, branch, summary, failing_checks? }`.

A sub-agent that cannot reach green returns `status: failed` with the failing checks — it does **not** merge anything itself. All reviewing and merging is done by the orchestrator in Phases 1.5–2. Sub-agents do **not** call Codex themselves (slash commands run in the main session, not sub-agent context).

## Phase 1.5 — Adversarial review gate (orchestrator, per green branch)

*(Skip entirely if `--no-review`.)* For every task in the wave that returned `status: green`, the **orchestrator** — not the sub-agent — runs an adversarial Codex review of that task's branch against the recorded base, before any merge.

**Why the orchestrator:** `/codex:*` are slash commands; they execute in the main session, not inside a worktree sub-agent. The review is therefore a gate the orchestrator applies to each green branch, sitting between fan-out (Phase 1) and integration (Phase 2).

**Run reviews concurrently across the wave, collect at the gate:**

1. For each green task, from its worktree (or with the branch checked out), kick off in the background:
   ```
   /codex:adversarial-review --base <recorded-base-commit> --background \
     focus on: faithfulness to the task's Relevant specs, security, data loss,
     race conditions, error handling, and whether a simpler/safer approach was available
   ```
   The steer text ties the review to *this* task's specs — an off-spec but green implementation is exactly what an adversarial pass should catch. Record the returned job id per task.
2. Poll with `/codex:status`; as each finishes, pull its findings with `/codex:result`.
3. **Adjudicate severity yourself from the review prose.** The command is read-only and returns a written critique, not a structured verdict, so the orchestrator classifies each finding:
   - **HIGH (blocks merge):** a real correctness/security/data-loss/concurrency defect; a violation of a `Relevant specs:` contract or a project standing constraint; a broken invariant the tests didn't catch. When in doubt whether something is high, treat a concrete exploitable/again-reproducible defect as high and a matter of taste as not.
   - **ADVISORY (does not block):** style, naming, non-critical perf, speculative concerns, "could also" suggestions, anything the specs don't require.
   - Prefer a structured severity if a future Codex version emits one; until then, judge the prose against these criteria.
4. **Verdict per task:**
   - No HIGH findings → the branch passes the gate; carry any ADVISORY notes into the final report and proceed to Phase 2 for that branch.
   - One or more HIGH findings → the task **fails the review gate**: it is not merged, and it goes to Phase 3 quarantine (same machinery as a failed test), with the HIGH findings recorded verbatim in the task file.

Review cost/latency is real: run wave reviews in the background so they overlap each other and any still-running work, and only serialize at the collection point. If Codex is rate-limited or errors (not a code finding, but a tool failure), report it and treat that task as **review-pending** → quarantine (don't merge unreviewed work when review was requested); the user can re-run it or pass `--no-review`.

## Phase 2 — Integrate (orchestrator, topological order)

Merge **one branch at a time**, in dependency order, on the base branch in the main working tree. Only branches that passed **both** the green gate (Phase 1) and the review gate (Phase 1.5) are eligible.

1. `git merge --no-ff impl/NN-slug` into base.
2. **On a merge conflict** → spawn a **resolver sub-agent**: give it the conflicted files, both task specs, and the instruction to reconcile faithfully to the specs (not to delete either side's intent). It resolves, commits the merge.
3. **Run the full suite on the merged base.** Integrated green is the real gate — per-worktree green can still break on integration.
   - Green → the merge stands; move to the next branch.
   - Red → spawn the resolver sub-agent to fix the integration (against the relevant specs) and re-run the suite. If it greens, the merge stands.
   - Still red after the resolver → **roll back this one merge** (`git reset --hard` to the pre-merge commit) and treat the task as failed (→ Phase 3 quarantine).

Merging after each branch (rather than all at once) is deliberate: it attributes any breakage to the specific feature that caused it. (Note: the adversarial review already ran per-branch pre-merge; integration here is about mechanical conflicts and integrated-suite green, not re-review.)

## Phase 3 — Failure handling (quarantine + skip dependents)

- A task that fails its worktree gate (Phase 1), its **review gate (Phase 1.5)**, or its integration gate (Phase 2) is **quarantined**: keep its `impl/NN-slug` branch (pushed), do **not** merge it, and append a `> blocked:` note under the relevant deliverable in `tasks/NN-*.md`. The note records the cause:
   - failing checks (test/build), **or**
   - `review: <HIGH findings, verbatim from Codex>` (so the human can act on the exact critique), **or**
   - unresolved merge/integration conflict.
- **Skip its transitive dependents.** Any task that (directly or transitively) `Depends on:` a quarantined task cannot be built on a missing prerequisite — mark each skipped task `> blocked: depends on quarantined NN` and do not spawn it.
- The run continues with every task whose dependency chain is fully merged. One bad task prunes its own subtree, nothing more.

## Phase 4 — Cleanup + report

1. **Push the base branch** (the merged result is the deliverable).
2. **Remove merged worktrees** (`git worktree remove`) and **delete their branches** local + remote (`git branch -d impl/NN-slug`; `git push origin --delete impl/NN-slug`). **Keep** quarantined branches and worktrees so the user can finish them by hand.
3. **Update `tasks/README.md`** — set the Status column: `done` for merged, `blocked` for quarantined/skipped.
4. **Report** to the user, concise and skimmable:
   - ✓ **Merged** (N): task list, each one line; note if it merged with ADVISORY review notes.
   - ✗ **Quarantined** (M): task + the cause — failing checks / **HIGH review findings** / conflict — and where its branch is.
   - ⏭ **Skipped** (K): task + which quarantined dependency blocked it.
   - **Review summary:** how many branches were reviewed, how many blocked on HIGH findings, notable advisory themes. (Omit if `--no-review`.)
   - Final base test status (the suite that gates the whole run), and the base branch HEAD.
   - If anything is quarantined: the one suggested next step (e.g. "resume task NN on its `impl/NN-slug` branch; the Codex review flagged ").

## Flags

- `--no-review` — skip Phase 1.5 entirely (green-gate only, the original behaviour). Use for trusted/mechanical backlogs or when Codex is unavailable and you want to proceed anyway.
- (existing) a `tasks/` path in `$ARGUMENTS` overrides cwd discovery.

## Principles

- **Faithful execution, not redesign.** The specs are the source of truth; implement them, surface deviations, never invent or silently cut scope. (Mirrors `/ingest`'s "faithful, not creative.")
- **The base branch is sacred.** It only ever advances through a clean merge that passed review and left the full suite green. A red or high-severity-flagged merge is rolled back or blocked, not shipped.
- **Two gates, two questions.** Green asks "does it work?"; the adversarial review asks "is it right, and was this the safe way?" A task must answer both before it merges.
- **Isolation buys parallelism; the DAG buys correctness.** Fan out only what's independent; sequence what isn't; let a failure prune its subtree rather than the whole run.
- **Verify with commands, not vibes.** "Done" means the `Definition of done` command exited zero — both per-worktree and on the integrated base. The review adjudication is the one judgment call, and it errs toward blocking on concrete defects.
- **Leave failures recoverable.** Quarantined work stays on a pushed branch with a `> blocked:` note (including the verbatim Codex critique) in the task file, so a human (or a later `/implement`) can pick it up exactly where it stalled.
- **The reviewer is adversarial by design.** Use `/codex:adversarial-review`, not `/codex:review` — the point is to challenge the approach, assumptions, and failure modes, not just lint the code. A second model with no stake in the implementation is the value.

## Field-tested gotchas (from real runs)

Hard-won lessons from live `/implement` runs (greenfield Plottle; brownfield ellisX; a concurrent two-orchestrator collision). Fold these into how the orchestrator and its sub-agents operate:

**Orchestrator hygiene**
- **Prefix every orchestrator git/test command with `cd <main-checkout> &&`.** The harness repoints the orchestrator's shell cwd into a notifying sub-agent's worktree between calls; an unqualified `git merge`/test then runs in the *wrong* tree and silently no-ops ("Already up to date" from inside a feature worktree, no merge actually done).
- **Never park uncommitted work in the main checkout while a run is live** (and never run two `/implement` orchestrators in the same repo). The integration path uses `git reset --hard` / `git merge --abort`; a sibling's reset will wipe your in-progress conflicted merge or your not-yet-committed baseline fixes. Commit anything in the main checkout **immediately**; do all conflict resolution on the *branch* in an isolated resolver worktree, then perform one atomic merge.
- **Guard every merge against a foreign in-flight merge:** before `git merge`, assert `[ ! -f .git/MERGE_HEAD ]` and no unmerged paths in `git status --porcelain`; wait-loop otherwise, and never `--abort` a conflict whose files don't belong to your branch (that cancels the other stream's merge).

**Integration gate**
- **Add a boot check to the integrated gate, alongside the suite.** A circular import (or other import-time break) can pass the whole pytest suite by import-order luck yet crash `uvicorn`/the entrypoint at startup. Run `python -c "import <app_module>"` (or the project's real boot command) after each merge, not just the tests.

**Environment / tooling**
- **`uv sync` alone omits the dev toolchain** — sub-agents that need pytest/ruff/mypy must `uv sync --extra dev` (plus any project extras), or the `Definition of done` command isn't even installed.
- **Exit plan mode before starting.** Sub-agents spawned while the parent session's plan-mode flag is set are harness-blocked from editing — even with `mode: acceptEdits` — so every worktree agent fails to write. Confirm plan mode is off in Phase 0.

## Distribution / maintenance (for the skill author)

Ships in the `kev` plugin of `proton-pidgeon/claude-skills` (marketplace `kevdunn`); reaches other hosts via `/plugin marketplace update kevdunn` + restart. It is the executing counterpart to `[[skill-understand]]`'s sibling `/ingest` (design docs → `specs/`+`tasks/`); the two share the `tasks/NN-*.md` contract (`Depends on:`, `Relevant specs:`, deliverable checkboxes, `Definition of done`). If that contract changes in `/ingest`, update Phase 0/1 here to match. Worktree-fanout, quarantine, and DAG-pipeline design decided 2026-05-30 with the user; adversarial Codex review gate (Phase 1.5, via `openai/codex-plugin-cc`'s `/codex:adversarial-review`, high-severity-blocks, on-by-default with `--no-review`) added 2026-07-07 with the user. The review gate depends on the external Codex plugin being installed and authed on the host — that plugin is not synced by `kevdunn`; note it in host setup.
