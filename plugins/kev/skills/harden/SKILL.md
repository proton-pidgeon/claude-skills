---
name: harden
description: Systematically triage and fix the findings of a code review — a Codex adversarial review (`/codex:adversarial-review`), a `/code-review`, or the `/implement` review gate — then verify green and commit, leaving a paper trail of what was fixed, deferred, and rejected. Use when the user runs `/harden`, or asks to "fix the review findings", "apply the codex review", "address the review comments", "harden this from the review", or "action the review". The executing counterpart to a review: a review finds problems; `/harden` fixes them. Local CLI/Desktop only — it edits code, runs the project's tests, and commits.
---

# /harden — systematically fix the outputs of a code review

Take the findings of a review — a Codex adversarial review, a `/code-review`, or the
high-severity findings the `/implement` gate quarantined on — and **action them**: triage each
finding honestly, fix the real ones (with a regression test where it's a correctness/security
bug), verify the suite is green, and commit with a record of every call made.

`/harden` is the executing half of the **review → harden** loop, the same shape as
`/ingest → /implement`: the review writes the critique; `/harden` fulfills the parts that are
real. It pairs directly with `/implement`'s Phase 1.5 gate — when that gate blocks a merge on a
high-severity finding, `/harden` is how you clear it — and with a standalone
`/codex:adversarial-review` or `/code-review` on a working diff.

## Operating rules

- **Adjudicate, don't obey.** A review is *evidence, not a work order.* Lighter review models
  (e.g. a ChatGPT-account Codex on `gpt-5.4-mini`) routinely overstate severity and flag
  deliberate scope decisions as defects. Every finding gets your own verdict — fix / defer /
  reject — with a reason. Never rubber-stamp; never silently drop a real one.
- **Faithful to scope.** A finding names a specific defect. Fix *that*. Do not redesign, do not
  scope-creep into changes the finding doesn't call for. (Same discipline as `/ingest`'s
  "faithful, not creative.")
- **Green or it didn't happen.** A fix is done only when the project's verify command exits zero
  — run it, don't reason about it — and the specific behavior the finding was about is
  re-exercised (boot the app, hit the endpoint), not just unit-tested.
- **Prove correctness/security fixes with a test.** For a bug or a leak, add a regression test
  that would have caught it. A fix with no test is a claim, not a fix.
- **Leave a paper trail.** The commit message records the triage — fixed / deferred (where) /
  rejected (why) — so a human can audit the calls later.
- **Local only.** Edits code, runs tests, commits. If `CLAUDE_CODE_REMOTE=true`, say so and stop.

## Phase 0 — Get the findings + preflight

1. **Resolve the findings.** In priority order, stop at the first that yields findings:
   - **Explicit argument** — a path to a review-output file, or findings pasted into the prompt.
   - **The most recent review in this session** — a Codex review output the orchestrator just
     ran (`/codex:result` / the review's output file), or a `/code-review` result.
   - **None yet** — offer to generate one: run `/codex:adversarial-review` (challenge review) or
     `/code-review` on the current diff, then proceed with its output. **Never invent findings.**
2. **Confirm Codex is usable** if you'll generate the review here. The gate/review uses the Codex
   plugin; a quick `/codex:setup` reports readiness. A ChatGPT-account login **cannot** use
   `gpt-5.5-codex` or `spark` (400s) — set `~/.codex/config.toml` `model` to a supported one
   (e.g. `gpt-5.4-mini`) or pass `--model`. If Codex is unusable and no findings were supplied,
   say so and stop rather than silently skipping the review.
3. **Establish a green baseline.** Detect the verify command (read `package.json` scripts,
   `Makefile`, `pyproject.toml`, `justfile`, CI config, or a project skill; ask if you can't tell
   — you cannot gate on green without it). **Run it once.** If the baseline is already red,
   report which checks fail and stop — hardening from red is meaningless.
4. **Record the anchor** — base branch + HEAD commit, for the commit and any rollback.

## Phase 1 — Triage (one verdict per finding)

The review's own severity label is a *hint*, not the answer. For each finding assign:

- **fix** — a real defect within the current scope → fix now.
- **defer** — real, but belongs to a later task/milestone (record *where* it goes and *why now
  is wrong*, e.g. "needs the full settings surface that lands in 01b").
- **reject** — not a real problem: a deliberate design choice, a false positive, or out of scope
  → record *why* it's not a defect.

Re-rank severity yourself. A finding that "meets the deliverable as written" but exposes a latent
risk downstream (a leak that only bites once real credentials arrive; a seam that will force a
rework two tasks later) is often worth fixing early *if cheap* — say so and fix it. Conversely,
a "high" that's overstated (a draft artifact nothing consumes yet) can be downgraded — say so.

**Print the triage table before touching code** (finding → verdict → one-line rationale), so the
plan is visible and interruptible.

## Phase 2 — Fix

- Apply the **fix** and worthwhile-**defer**-that's-actually-cheap items, staying inside each
  finding's scope. Group into logical commits (one concern per commit).
- For each correctness or security finding, **add a regression test** alongside the fix.
- Iterate the verify command until it is green.

## Phase 3 — Verify + commit

1. **Full suite green** is the gate — run it, don't assume it. Then **re-exercise the actual
   behavior** each finding was about (start the process, hit the route, run the CLI path).
2. **Commit** with a message that records the triage: fixed (per finding, one line each),
   deferred (+ target task), rejected (+ reason). Follow the repo's norms — on a feature branch
   land per house convention; on Kev's solo daily-driver repos commit straight to `main`
   (`[[feedback-commit-to-main-solo-repos]]`).
3. **Close the loop (optional, offer it):** re-run the review on the new diff to confirm the
   high-severity findings are actually gone — a review that still flags them means the fix missed.

## Phase 4 — Report

Concise and skimmable:
- ✅ **Fixed** (N): finding → what changed (one line), and the test that now guards it.
- ⏭ **Deferred** (M): finding → where it now lives and why.
- ✕ **Rejected** (K): finding → why it isn't a defect.
- Final verify status (the command + result) and the base HEAD.
- If you closed the loop, the re-review verdict.

## Principles

- **Adjudicate, don't obey.** The review is input to your judgment, not a checklist to execute
  blindly. Lighter models overstate; deliberate decisions get mis-flagged.
- **Fix the real ones, prove them.** Tests + green, or it's a claim.
- **Faithful to scope.** Fix the named defect; never redesign or scope-creep.
- **Surface deferrals and rejections with reasons.** Like `/ingest` surfaces ambiguity rather
  than silently resolving it — the calls you *didn't* act on are as important as the ones you did.
- **Verify with commands, not vibes.**

## Distribution / maintenance (for the skill author)

Ships in the `kev` plugin of `proton-pidgeon/claude-skills` (marketplace `kevdunn`); reaches
other hosts on `/plugin marketplace update kevdunn` + `claude plugin update kev` + restart (fan
out with `/fleet`). **Bump `plugin.json` `version` on any content change here** or `plugin
update` no-ops on the version collision (`[[claude-skills-version-bump-gotcha]]`). Pairs with the
`/implement` review gate (Phase 1.5) and the Codex plugin (`openai/codex-plugin-cc`); if the
`/codex:*` command surface changes, update Phase 0 here to match.
