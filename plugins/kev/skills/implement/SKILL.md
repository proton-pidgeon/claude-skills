---
name: implement
description: Autonomously implement a `tasks/`-based backlog (as produced by `/ingest`) by fanning out one worktree-isolated sub-agent per task along the dependency DAG, gating each on a green test/build, then merging everything back into the base branch and cleaning up. Use when the user runs `/implement`, or asks to "implement the tasks/backlog", "build out the specs", "work through tasks/ in parallel", or "execute the implementation plan". Local CLI/Desktop only — it creates git worktrees and runs the project's tests.
---

# /implement — autonomous, worktree-isolated, DAG-parallel implementation

Take a `tasks/` backlog (the output of `/ingest`: `tasks/NN-<slug>.md` files + `tasks/README.md`, each task declaring `Depends on:`, `Relevant specs:`, deliverable checkboxes, and a `Definition of done`) and **build it** — fanning out one sub-agent per task, each in its own git worktree, in dependency order, gating each on a green test/build, then merging the lot back into the base branch and cleaning up.

This skill is the executing half of the `/ingest → /implement` pipeline. `/ingest` writes the contract; `/implement` fulfills it. It runs **fully autonomously** once started: no per-task approval gate. Its safety comes from worktree isolation, the green gate, quarantine-on-failure, and the fact that nothing reaches the base branch until it passes the suite.

## Operating rules

- **The task files are the contract.** Each `tasks/NN-*.md` plus its `Relevant specs:` is self-sufficient (that's an `/ingest` guarantee). Implement to the spec; do **not** invent scope the task doesn't declare, and do **not** silently drop a declared deliverable.
- **Green or it didn't happen.** A task is "done" only when its `Definition of done` passes — run the real command, don't reason about it. Integrated green (full suite on the merged base) is a separate, stricter gate than per-worktree green.
- **Isolate, then integrate.** Every task is built in its own worktree on its own branch. Nothing touches the base branch until it has merged cleanly and the suite is green.
- **Quarantine, don't abort.** One task failing its gate must not sink the run. Quarantine it and press on with everything that doesn't depend on it.
- **Local only.** This skill creates git worktrees and runs the project's test/build. It is not designed for cloud sessions; if `CLAUDE_CODE_REMOTE=true`, say so and stop.
- **Push is backup, not publication.** Feature branches are pushed for off-machine safety and deleted once merged. No PRs are opened (per design) — the deliverable is merged commits on the base branch.

## Phase 0 — Preflight (do all of this before spawning anything)

1. **Refuse cloud.** If `CLAUDE_CODE_REMOTE=true`, stop with a one-line explanation — worktrees + long test runs are a local-only operation.
2. **Locate the backlog.** Find `tasks/` (cwd first; honor a path in `$ARGUMENTS`). If absent, tell the user to run `/ingest` first (or point you at the tasks dir). Read `tasks/README.md` and every `tasks/NN-*.md`.
3. **Build the DAG.** Parse each task's `Depends on:` (and the `Depends on` column in `tasks/README.md`) into a dependency graph. Treat sub-tasks (`04a`, `04b`, …) as nodes under their parent's ordering. **Reject cycles** — if the graph has one, report the cycle and stop; the backlog is malformed.
4. **Confirm a clean, green baseline.**
   - The working tree must be clean (no uncommitted changes) and on a sensible base branch. If dirty, stop and ask the user to commit/stash.
   - Detect the project's test/build command (read `package.json` scripts, `Makefile`, `pyproject.toml`, `justfile`, CI config, or a project skill). If you cannot determine how to verify, **ask** — you cannot gate on green without it.
   - **Run it once on the base.** If the baseline is already red, **abort**: gating on green is meaningless from a red start. Report which tests fail and stop.
   - Record the base branch name and its HEAD commit — this is the merge target and the rollback anchor.
5. **Plan the waves.** Topologically sort the DAG into waves (a wave = all tasks whose dependencies are already merged). Print the plan: the wave order, which tasks run in parallel, and the verify command. Then proceed (no approval gate — but the plan is on screen so an interrupt is possible).

## Phase 1 — Fan out per wave (worktree-isolated sub-agents)

Process waves in order. Within a wave, fan out **concurrently** — one sub-agent per task, each with `isolation: worktree` (or an explicit `git worktree add ../<repo>-impl-NN impl/NN-slug` off the recorded base commit). Cap concurrency at roughly CPU-cores − 2; excess tasks queue.

Each task's sub-agent is given **only** its `tasks/NN-*.md` and the files its `Relevant specs:` point to, and told to:

1. Read the task file + linked specs. The deliverables and `Definition of done` are the checklist.
2. Implement the **Deliverables**, staying within scope (respect `Anti-deliverables`).
3. **Run the `Definition of done` to green.** Iterate until the verify command passes. Tick the `- [ ]` boxes in its own copy of the task file as each is satisfied.
4. Commit incrementally (one logical change per commit, per the task file's "Notes for Claude Code") on `impl/NN-slug`.
5. **Push the branch** (`git push -u origin impl/NN-slug`) as an off-machine backup.
6. Return a structured result: `{ task, status: green|failed, branch, summary, failing_checks? }`.

A sub-agent that cannot reach green returns `status: failed` with the failing checks — it does **not** merge anything itself. All merging is done by the orchestrator in Phase 2.

## Phase 2 — Integrate (orchestrator, topological order)

Merge **one branch at a time**, in dependency order, on the base branch in the main working tree:

1. `git merge --no-ff impl/NN-slug` into base.
2. **On a merge conflict** → spawn a **resolver sub-agent**: give it the conflicted files, both task specs, and the instruction to reconcile faithfully to the specs (not to delete either side's intent). It resolves, commits the merge.
3. **Run the full suite on the merged base.** Integrated green is the real gate — per-worktree green can still break on integration.
   - Green → the merge stands; move to the next branch.
   - Red → spawn the resolver sub-agent to fix the integration (against the relevant specs) and re-run the suite. If it greens, the merge stands.
   - Still red after the resolver → **roll back this one merge** (`git reset --hard` to the pre-merge commit) and treat the task as failed (→ Phase 3 quarantine).

Merging after each branch (rather than all at once) is deliberate: it attributes any breakage to the specific feature that caused it.

## Phase 3 — Failure handling (quarantine + skip dependents)

- A task that fails its worktree gate (Phase 1) or its integration gate (Phase 2) is **quarantined**: keep its `impl/NN-slug` branch (pushed), do **not** merge it, and append `> blocked: <reason — failing checks / unresolved conflict>` under the relevant deliverable in `tasks/NN-*.md`.
- **Skip its transitive dependents.** Any task that (directly or transitively) `Depends on:` a quarantined task cannot be built on a missing prerequisite — mark each skipped task `> blocked: depends on quarantined NN` and do not spawn it.
- The run continues with every task whose dependency chain is fully merged. One bad task prunes its own subtree, nothing more.

## Phase 4 — Cleanup + report

1. **Push the base branch** (the merged result is the deliverable).
2. **Remove merged worktrees** (`git worktree remove`) and **delete their branches** local + remote (`git branch -d impl/NN-slug`; `git push origin --delete impl/NN-slug`). **Keep** quarantined branches and worktrees so the user can finish them by hand.
3. **Update `tasks/README.md`** — set the Status column: `done` for merged, `blocked` for quarantined/skipped.
4. **Report** to the user, concise and skimmable:
   - ✓ **Merged** (N): task list, each one line.
   - ✗ **Quarantined** (M): task + the failing checks / conflict, and where its branch is.
   - ⏭ **Skipped** (K): task + which quarantined dependency blocked it.
   - Final base test status (the suite that gates the whole run), and the base branch HEAD.
   - If anything is quarantined: the one suggested next step (e.g. "resume task NN on its `impl/NN-slug` branch").

## Principles

- **Faithful execution, not redesign.** The specs are the source of truth; implement them, surface deviations, never invent or silently cut scope. (Mirrors `/ingest`'s "faithful, not creative.")
- **The base branch is sacred.** It only ever advances through a clean merge that left the full suite green. A red merge is rolled back, not shipped.
- **Isolation buys parallelism; the DAG buys correctness.** Fan out only what's independent; sequence what isn't; let a failure prune its subtree rather than the whole run.
- **Verify with commands, not vibes.** "Done" means the `Definition of done` command exited zero — both per-worktree and on the integrated base.
- **Leave failures recoverable.** Quarantined work stays on a pushed branch with a `> blocked:` note in the task file, so a human (or a later `/implement`) can pick it up exactly where it stalled.

## Distribution / maintenance (for the skill author)

Ships in the `kev` plugin of `proton-pidgeon/claude-skills` (marketplace `kevdunn`); reaches other hosts via `/plugin marketplace update kevdunn` + restart. It is the executing counterpart to `[[skill-understand]]`'s sibling `/ingest` (design docs → `specs/`+`tasks/`); the two share the `tasks/NN-*.md` contract (`Depends on:`, `Relevant specs:`, deliverable checkboxes, `Definition of done`). If that contract changes in `/ingest`, update Phase 0/1 here to match. Worktree-fanout, quarantine, and DAG-pipeline design decided 2026-05-30 with the user.
