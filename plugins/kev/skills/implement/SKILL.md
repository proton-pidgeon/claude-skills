---
name: implement
description: Autonomously implement a `tasks/`-based backlog (as produced by `/ingest`) by fanning out one worktree-isolated sub-agent per task along the dependency DAG, gating each on a green test/build AND a cross-lineage review (GPT-5 finds defects, a Fable adjudicator judges them), with a Sonnet→Opus→Fable→GPT-5 escalation ladder, then merging everything back into the base branch and cleaning up. Use when the user runs `/implement`, or asks to "implement the tasks/backlog", "build out the specs", "work through tasks/ in parallel", or "execute the implementation plan". Local CLI/Desktop only — it creates git worktrees, runs the project's tests, and calls the Codex plugin for review.
---

# /implement — autonomous, worktree-isolated, DAG-parallel implementation

Take a `tasks/` backlog (the output of `/ingest`: `tasks/NN-<slug>.md` files + `tasks/README.md`, each task declaring `Depends on:`, `Relevant specs:`, deliverable checkboxes, and a `Definition of done`) and **build it** — fanning out one sub-agent per task, each in its own git worktree, in dependency order, gating each on a green test/build **and an adversarial Codex review**, then merging the lot back into the base branch and cleaning up.

This skill is the executing half of the `/ingest → /implement` pipeline. `/ingest` writes the contract; `/implement` fulfills it. It runs **fully autonomously** once started: no per-task approval gate. Its safety comes from worktree isolation, the green gate, the adversarial-review gate, quarantine-on-failure, and the fact that nothing reaches the base branch until it passes both gates.

## Operating rules

- **The task files are the contract.** Each `tasks/NN-*.md` plus its `Relevant specs:` is self-sufficient (that's an `/ingest` guarantee). Implement to the spec; do **not** invent scope the task doesn't declare, and do **not** silently drop a declared deliverable.
- **Green or it didn't happen.** A task is "done" only when its `Definition of done` passes — run the real command, don't reason about it. Integrated green (full suite on the merged base) is a separate, stricter gate than per-worktree green.
- **Reviewed or it doesn't merge.** After green, each task's branch faces an adversarial GPT-5 (Codex) review, whose findings a dedicated Fable adjudicator judges (Phase 1.5). A high-severity verdict blocks the merge exactly as a red test would. On by default; `--no-review` opts out.
- **Isolate, then integrate.** Every task is built in its own worktree on its own branch. Nothing touches the base branch until it has passed green + review, merged cleanly, and left the suite green.
- **Quarantine, don't abort.** One task failing any gate must not sink the run. Quarantine it and press on with everything that doesn't depend on it.
- **Local only.** This skill creates git worktrees, runs the project's test/build, and invokes the Codex plugin. It is not designed for cloud sessions; if `CLAUDE_CODE_REMOTE=true`, say so and stop.
- **Push is backup, not publication.** Feature branches are pushed for off-machine safety and deleted once merged. No PRs are opened (per design) — the deliverable is merged commits on the base branch.
- **Route each stage to the right model.** Spend cheap where a gate catches mistakes; spend the top model where nothing does. See Model routing below — it's a first-class part of how the pipeline works, not an optimization to bolt on later.

## Model routing

`/implement` is multi-model along **two axes**, and every spawn should name its model explicitly rather than inheriting the session default.

- **Axis 1 — the Claude cost/capability ladder** (`haiku → sonnet → opus → fable`), set via the Agent tool's per-spawn `model` parameter. Same lineage, more capability as you climb. This is how implementation, resolution, adjudication, and reporting are tiered.
- **Axis 2 — cross-provider (Claude ↔ GPT-5)** via the Codex plugin (`/codex:adversarial-review`, `codex-rescue`). A *different training lineage* — used where an independent perspective beats more of the same. GPT-5 can't be a worktree `model`; it's reached at the orchestrator level (which is exactly why the review already runs from the orchestrator, not the sub-agent).

**Stage → model:**

| Stage | Model | Why |
|---|---|---|
| P0 Preflight (orchestrator) | Opus 4.8 (session) | holds the DAG; runs once |
| P1 Implementation (worktree agents) | **`sonnet`** default (**`opus`** for high-risk tasks) | the bulk of the spend; Sonnet 5 codes at near-Opus quality and is backstopped by the green + review gates |
| P1.5 Reviewer | **GPT-5** (Codex) | cross-lineage defect finding |
| P1.5 Adjudicator | **`fable`** (dedicated agent) | the one judgment with no backstop below it; an open-ended severity call is Fable's strength, not its weakness; low-volume so the premium is bounded |
| P2 Resolver | **`opus`** → **`fable`** if gnarly → `codex-rescue` if stuck | touches the sacred base branch |
| P4 Report / cleanup | **`haiku`** | pure formatting |

Reviewer (GPT-5) + Adjudicator (Fable) is a deliberate **cross-lineage gate**: one family finds and argues the defects, a *different* family independently judges whether they block — not one model marking its own homework.

The **escalation ladder** (below) is the spine that ties both axes together: a task that fails a gate climbs `sonnet → opus → fable → GPT-5` before it's ever quarantined, so the expensive/slow tiers only ever touch the handful of tasks that earn them.

## Phase 0 — Preflight (do all of this before spawning anything)

1. **Refuse cloud.** If `CLAUDE_CODE_REMOTE=true`, stop with a one-line explanation — worktrees + long test runs are a local-only operation.
2. **Locate the backlog.** Find `tasks/` (cwd first; honor a path in `$ARGUMENTS`). If absent, tell the user to run `/ingest` first (or point you at the tasks dir). Read `tasks/README.md` and every `tasks/NN-*.md`.
3. **Build the DAG.** Parse each task's `Depends on:` (and the `Depends on` column in `tasks/README.md`) into a dependency graph. Treat sub-tasks (`04a`, `04b`, …) as nodes under their parent's ordering. **Reject cycles** — if the graph has one, report the cycle and stop; the backlog is malformed.
4. **Confirm a clean, green baseline.**
   - The working tree must be clean (no uncommitted changes) and on a sensible base branch. If dirty, stop and ask the user to commit/stash.
   - Detect the project's test/build command (read `package.json` scripts, `Makefile`, `pyproject.toml`, `justfile`, CI config, or a project skill). If you cannot determine how to verify, **ask** — you cannot gate on green without it.
   - **Run it once on the base.** If the baseline is already red, the default is to **abort**: gating on green is meaningless from a red start. Report which tests fail and stop. **But brownfield repos are often red on `main` for reasons orthogonal to the backlog** (a coverage-gate threshold, pre-existing lint/type drift, an ordering-flaky singleton test). In that case, offer the user one of two paths rather than a dead stop: (a) **fix the red baseline first as its own task** — attribute each failure via `git log -S`/`git show`, repair the *test* to encode the deliberate product change (never relax an assertion to vacuity); or (b) switch to **differential gating** — run tests green with the coverage gate off (e.g. `pytest --no-cov`), and require *zero new* lint/type findings versus a per-branch baseline you capture up front, rather than an absolute-zero bar. Pick this only with the user's nod; note it in the plan so the weaker gate is on the record.
   - Record the base branch name and its HEAD commit — this is the merge target, the review base (`--base`), and the rollback anchor.
5. **Confirm the review gate is usable** (unless `--no-review`). The gate uses the Codex plugin (`openai/codex-plugin-cc`) for the GPT-5 reviewer. Check that `/codex:*` commands are available and Codex is authenticated — a quick `/codex:setup` reports readiness. **If Codex is not installed/authed:** tell the user, and ask whether to proceed with `--no-review` (green-gate only) or stop to fix Codex. Never silently skip the review the user asked for.
6. **Confirm the Fable rungs are usable.** The Fable adjudicator (Phase 1.5) and the Fable escalation rung require `claude-fable-5`, which is **not available under zero data retention** — needs a 30-day-retention org. If the org can't reach Fable, degrade gracefully: adjudicate on `opus` instead and cap the escalation ladder at Opus (note the degrade in the plan). Don't hard-fail the run over it.
7. **Plan the waves.** Topologically sort the DAG into waves (a wave = all tasks whose dependencies are already merged). Print the plan: the wave order, which tasks run in parallel, the verify command, the per-task **starting rung** (see Escalation ladder), and whether the review gate is on. Then proceed (no approval gate — but the plan is on screen so an interrupt is possible).

## Phase 1 — Fan out per wave (worktree-isolated sub-agents)

Process waves in order. Within a wave, fan out **concurrently** — one sub-agent per task, each with `isolation: worktree` (or an explicit `git worktree add ../<repo>-impl-NN impl/NN-slug`). Cap concurrency at roughly CPU-cores − 2; excess tasks queue.

**Spawn each task at its starting rung (default `model: sonnet`).** Sonnet 5 codes at near-Opus quality and is the right default for the bulk — a subtle miss is caught by the green gate and the review gate, then the escalation ladder retries it higher. Start a task at `model: opus` instead when the orchestrator infers it's **high-risk**: its `Relevant specs:` or deliverables touch security / auth / crypto / concurrency / migration / schema, or the task is unusually large (many deliverables / long specs). This is a *starting*-rung heuristic only — a mis-called task still climbs the ladder on failure. (A future `/ingest`/`/feature` `Complexity:` hint in the task file can override the inference; until then, infer.)

**Branch each wave off the *current* base HEAD, not the frozen Phase-0 baseline.** A wave's worktrees must include everything prior waves already merged, or a task won't see its own merged dependencies. So the base for wave *k* is base-branch HEAD *after* waves 1…*k*−1 merged — not the commit you recorded in Phase 0. Have each sub-agent make `git checkout -B impl/NN <current-base-HEAD>` its **first** step rather than trusting the worktree snapshot, which the harness can cut stale (pre-merge). Also **copy any git-ignored `.env`/secrets into each worktree right after creating it** — `git worktree add` only carries committed files, so a task whose `Definition of done` needs live keys otherwise runs against an empty env and fails silently. For heavy shared deps (torch/whisper/etc.), build one `<repo>/.venv` once and point every worktree agent's commands at its absolute path instead of installing per-worktree.

Each task's sub-agent is given **only** its `tasks/NN-*.md` and the files its `Relevant specs:` point to, and told to:

1. Read the task file + linked specs. The deliverables and `Definition of done` are the checklist.
2. Implement the **Deliverables**, staying within scope (respect `Anti-deliverables`).
3. **Run the `Definition of done` to green.** Iterate until the verify command passes. Tick the `- [ ]` boxes in its own copy of the task file as each is satisfied.
4. Commit incrementally (one logical change per commit, per the task file's "Notes for Claude Code") on `impl/NN-slug`.
5. **Push the branch** (`git push -u origin impl/NN-slug`) as an off-machine backup.
6. Return a structured result: `{ task, status: green|failed, branch, summary, failing_checks? }`.

A sub-agent that cannot reach green returns `status: failed` with the failing checks — it does **not** merge anything itself. All reviewing and merging is done by the orchestrator in Phases 1.5–2. Sub-agents do **not** call Codex themselves (slash commands run in the main session, not sub-agent context).

## Phase 1.5 — Cross-lineage review gate (orchestrator, per green branch)

*(Skip entirely if `--no-review`.)* For every task in the wave that returned `status: green`, the **orchestrator** runs a two-part gate before any merge: a **GPT-5 reviewer** finds and argues the defects, and a **dedicated Fable adjudicator** independently judges whether they block. Two different training lineages on the one decision with no backstop below it — not one model marking its own homework.

**Why the orchestrator runs it:** `/codex:*` are slash commands; they execute in the main session, not inside a worktree sub-agent. The gate therefore sits at the orchestrator, between fan-out (Phase 1) and integration (Phase 2).

**Step A — Review (GPT-5). Run reviews concurrently across the wave:**

1. For each green task, from its worktree (or with the branch checked out), kick off in the background:
   ```
   /codex:adversarial-review --base <recorded-base-commit> --background \
     focus on: faithfulness to the task's Relevant specs, security, data loss,
     race conditions, error handling, and whether a simpler/safer approach was available
   ```
   The steer text ties the review to *this* task's specs — an off-spec but green implementation is exactly what an adversarial pass should catch. Record the returned job id per task.
2. Poll with `/codex:status`; as each finishes, pull its findings with `/codex:result`.
   - **`--panel`:** also spawn an **Opus co-reviewer** agent (`model: opus`) per branch against the same base, prompted adversarially with the same focus. The adjudicator then judges the **union** of the GPT-5 and Opus findings. Off by default (roughly doubles review cost); reserve it for high-risk backlogs.

**Step B — Adjudicate (Fable). One dedicated agent per reviewed branch:**

3. For each branch, spawn a **Fable adjudicator** (`model: fable`) — run in the background across the wave, like the reviews. Hand it **only**: the review prose (GPT-5, plus the Opus co-reviewer's under `--panel`), the branch diff vs the recorded base, and the task's `Relevant specs:`. Its job is the open-ended judgment the reviewer can't make about its own output — classifying each finding and returning a **structured verdict**:
   ```
   { blocks: true|false, findings: [ { severity: HIGH|ADVISORY, summary, rationale } ] }
   ```
   Severity criteria for the adjudicator:
   - **HIGH (blocks merge):** a real correctness/security/data-loss/concurrency defect; a violation of a `Relevant specs:` contract or a project standing constraint; a broken invariant the tests didn't catch. When in doubt, treat a concrete exploitable/reproducible defect as high and a matter of taste as not.
   - **ADVISORY (does not block):** style, naming, non-critical perf, speculative concerns, "could also" suggestions, anything the specs don't require.
   - Enable the **Fable→Opus refusal fallback** on this agent (server-side `fallbacks: [{model: "claude-opus-4-8"}]`) so a safety-classifier refusal on security-adjacent diffs doesn't stall the gate. If the org can't reach Fable at all (Phase 0 degrade), adjudicate on `model: opus` instead.
4. **Verdict per task** (from the adjudicator's structured output):
   - `blocks: false` → the branch passes the gate; carry any ADVISORY notes into the final report and proceed to Phase 2 for that branch.
   - `blocks: true` → the task **fails the review gate**: it is not merged. Route it to the **escalation ladder** (below); it lands in Phase 3 quarantine only if the top rung still can't satisfy the gate, with the HIGH findings recorded verbatim in the task file.

Cost/latency is real: run both the reviews and the adjudications in the background so they overlap each other and any still-running work, and only serialize at the collection point. If the reviewer (Codex) is rate-limited or errors — a *tool* failure, not a code finding — report it and treat that task as **review-pending** → quarantine (don't merge unreviewed work when review was requested); the user can re-run it or pass `--no-review`.

## Phase 2 — Integrate (orchestrator, topological order)

Merge **one branch at a time**, in dependency order, on the base branch in the main working tree. Only branches that passed **both** the green gate (Phase 1) and the review gate (Phase 1.5) are eligible.

1. `git merge --no-ff impl/NN-slug` into base.
2. **On a merge conflict** → spawn a **resolver sub-agent** at `model: opus` (the base branch is sacred — resolution is high-stakes): give it the conflicted files, both task specs, and the instruction to reconcile faithfully to the specs (not to delete either side's intent). It resolves, commits the merge. If Opus can't reconcile it cleanly, escalate the resolver to `model: fable`; if a truly stuck conflict resists even that, hand it to `codex-rescue` (GPT-5, a different lineage) for one independent pass **before** rolling back.
3. **Run the full suite on the merged base.** Integrated green is the real gate — per-worktree green can still break on integration.
   - Green → the merge stands; move to the next branch.
   - Red → spawn the `opus` resolver sub-agent to fix the integration (against the relevant specs) and re-run the suite. If it greens, the merge stands. Same escalation as above (Opus → Fable → `codex-rescue`) if it can't.
   - Still red after the ladder → **roll back this one merge** (`git reset --hard` to the pre-merge commit) and treat the task as failed (→ Phase 3 quarantine).

Merging after each branch (rather than all at once) is deliberate: it attributes any breakage to the specific feature that caused it. (Note: the adversarial review already ran per-branch pre-merge; integration here is about mechanical conflicts and integrated-suite green, not re-review.)

## Escalation ladder (the spine — sits between failure and quarantine)

A task that fails a gate does **not** quarantine on first failure. It climbs a ladder, and only quarantines if the **top rung** still can't satisfy the gate. The first three rungs add *capability* (same lineage, bigger model); the last adds *diversity* (a different lineage breaks ruts that capability alone won't):

```
sonnet 5  →  opus 4.8  →  fable 5  →  GPT-5 (codex-rescue)  →  quarantine
└──── Axis 1: capability rungs ────┘   └─ Axis 2: diversity rung ─┘
```

- **Trigger:** a task fails its **green gate** (Phase 1 — can't reach green) **or** its **review gate** (Phase 1.5 — adjudicator returns `blocks: true`). Either sends it up the ladder.
- **Starting rung:** the rung the orchestrator assigned in Phase 1 (default `sonnet`, or `opus` for high-risk tasks). A task never *descends* — it resumes from the next rung above where it failed.
- **Each climb** re-runs the task on a fresh worktree at the higher `model`, then re-runs **both** gates (green, then review). Give the higher-tier agent the prior rung's failing checks / HIGH findings as context so it fixes the specific gap, not the whole task from scratch.
- **The `fable` rungs** carry the Fable→Opus refusal fallback (as in Phase 1.5). If the org can't reach Fable at all (Phase 0 degrade), the ladder is `sonnet → opus → codex-rescue`.
- **The GPT-5 rung** is `codex-rescue` — an independent implementation pass from a different provider. It's the last thing tried before quarantine, on the theory that a different lineage is more likely to break a rut than a bigger Claude.
- **Cost is bounded** because the ladder is failure-gated: the vast majority of tasks green on `sonnet` at the first rung and never climb. Only the ones that fight back reach the expensive/slow tiers.

## Phase 3 — Failure handling (quarantine + skip dependents)

- A task is **quarantined** only once it has **exhausted the escalation ladder** — i.e. the top rung still fails its worktree gate (Phase 1), its **review gate (Phase 1.5)**, or its integration gate (Phase 2). Quarantine is the ladder's terminal state, not a task's first failure. Keep its `impl/NN-slug` branch (pushed), do **not** merge it, and append a `> blocked:` note under the relevant deliverable in `tasks/NN-*.md`. The note records the cause **and the rung reached**:
   - failing checks (test/build), **or**
   - `review: <HIGH findings, verbatim from Codex>` (so the human can act on the exact critique), **or**
   - unresolved merge/integration conflict.
- **Skip its transitive dependents.** Any task that (directly or transitively) `Depends on:` a quarantined task cannot be built on a missing prerequisite — mark each skipped task `> blocked: depends on quarantined NN` and do not spawn it.
- The run continues with every task whose dependency chain is fully merged. One bad task prunes its own subtree, nothing more.

## Phase 4 — Cleanup + report

1. **Push the base branch** (the merged result is the deliverable).
2. **Remove merged worktrees** (`git worktree remove`) and **delete their branches** local + remote (`git branch -d impl/NN-slug`; `git push origin --delete impl/NN-slug`). **Keep** quarantined branches and worktrees so the user can finish them by hand.
3. **Update `tasks/README.md`** — set the Status column: `done` for merged, `blocked` for quarantined/skipped.
4. **Report** to the user, concise and skimmable. This is pure formatting over the run's outcome data — spawn the summarizer at **`model: haiku`** (or just write it inline if trivial). Cover:
   - ✓ **Merged** (N): task list, each one line; note the **rung** each landed on (e.g. `sonnet`, or `opus (escalated)`) and any ADVISORY review notes.
   - ✗ **Quarantined** (M): task + the cause — failing checks / **HIGH review findings** / conflict — the **top rung reached**, and where its branch is.
   - ⏭ **Skipped** (K): task + which quarantined dependency blocked it.
   - **Review summary:** how many branches were reviewed, how many blocked on HIGH findings (and whether `--panel` was on), notable advisory themes. (Omit if `--no-review`.)
   - **Model spend, roughly:** how many tasks stayed on `sonnet` vs escalated, and whether any Fable/`codex-rescue` rungs fired — the signal for whether the routing paid off.
   - Final base test status (the suite that gates the whole run), and the base branch HEAD.
   - If anything is quarantined: the one suggested next step (e.g. "resume task NN on its `impl/NN-slug` branch; the review flagged …").

## Flags

- `--no-review` — skip Phase 1.5 entirely (green-gate only, the original behaviour). This also skips the Fable adjudicator (there's nothing to adjudicate). Use for trusted/mechanical backlogs or when Codex is unavailable and you want to proceed anyway.
- `--panel` — in Phase 1.5, add an Opus co-reviewer alongside the GPT-5 reviewer; the Fable adjudicator judges the union of both reviews. Off by default (roughly doubles review cost); use it on high-risk backlogs where broader coverage is worth it.
- (existing) a `tasks/` path in `$ARGUMENTS` overrides cwd discovery.

## Principles

- **Faithful execution, not redesign.** The specs are the source of truth; implement them, surface deviations, never invent or silently cut scope. (Mirrors `/ingest`'s "faithful, not creative.")
- **The base branch is sacred.** It only ever advances through a clean merge that passed review and left the full suite green. A red or high-severity-flagged merge is rolled back or blocked, not shipped.
- **Two gates, two questions.** Green asks "does it work?"; the adversarial review asks "is it right, and was this the safe way?" A task must answer both before it merges.
- **Match the model to the blast radius.** Cheap where a gate catches the mistake (implementation → `sonnet`); the top model where nothing catches it (the merge-blocking judgment → `fable`; the sacred base branch → `opus`+). The escalation ladder means you never have to guess a task's tier up front — a gate failure buys the next rung.
- **The gate is cross-lineage on purpose.** The GPT-5 reviewer finds the defects; a *different* family (Fable) judges whether they block; a *different* family again (GPT-5 `codex-rescue`) is the last rung before quarantine. Independence across training lineages catches what more of the same lineage won't — which is the whole point of a review a model can't do on its own output.
- **Isolation buys parallelism; the DAG buys correctness.** Fan out only what's independent; sequence what isn't; let a failure prune its subtree rather than the whole run.
- **Verify with commands, not vibes.** "Done" means the `Definition of done` command exited zero — both per-worktree and on the integrated base. The Fable adjudicator's verdict is the one judgment call, and it errs toward blocking on concrete defects.
- **Leave failures recoverable.** Quarantined work stays on a pushed branch with a `> blocked:` note (including the verbatim review critique and the rung reached) in the task file, so a human (or a later `/implement`) can pick it up exactly where it stalled.
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

Ships in the `kev` plugin of `proton-pidgeon/claude-skills` (marketplace `kevdunn`); reaches other hosts via `/plugin marketplace update kevdunn` + restart. It is the executing counterpart to `[[skill-understand]]`'s sibling `/ingest` (design docs → `specs/`+`tasks/`); the two share the `tasks/NN-*.md` contract (`Depends on:`, `Relevant specs:`, deliverable checkboxes, `Definition of done`). If that contract changes in `/ingest`, update Phase 0/1 here to match. Worktree-fanout, quarantine, and DAG-pipeline design decided 2026-05-30 with the user; adversarial Codex review gate (Phase 1.5, via `openai/codex-plugin-cc`'s `/codex:adversarial-review`, high-severity-blocks, on-by-default with `--no-review`) added 2026-07-07 with the user. **Multi-model routing added 2026-07-10 with the user** (two axes — the Claude `haiku→sonnet→opus→fable` ladder via the Agent tool's per-spawn `model`, and cross-provider Claude↔GPT-5 via the Codex plugin): `sonnet` implements, `opus` resolves, a dedicated **Fable adjudicator** judges the GPT-5 review (a cross-lineage gate), `haiku` reports, and a failure-gated **escalation ladder** (`sonnet → opus → fable → codex-rescue`) climbs before quarantine. `--panel` adds an Opus co-reviewer. The routing is unverified by a live run — the first real `/implement` should confirm the ladder + Fable adjudicator behave and fold any gotchas into "Field-tested gotchas" above. The review + Fable rungs depend on the external Codex plugin (installed + authed) and a Fable-capable (non-ZDR) org respectively — neither is synced by `kevdunn`; note both in host setup.
