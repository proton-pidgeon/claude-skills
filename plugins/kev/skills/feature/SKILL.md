---
name: feature
description: Author a rigorous, spec-driven design plan for a NEW feature in an existing project, then write it out as numbered design docs that `/ingest` can turn straight into specs/ and tasks/. Plan-first — investigate the codebase, clarify scope, present a plan for approval, and only write the docs once the user signs off. Use when the user runs `/feature`, or asks to "plan a new feature", "spec out a feature for this project", "write a design doc for X", or "design feature X so we can ingest and build it".
---

# /feature — design a new feature → `/ingest`-ready design docs

Turn a feature idea into a set of **numbered, spec-driven design documents** in the current
project, shaped so the very next step can be `/ingest` → `specs/` + `tasks/` → `/implement`.

`/feature` is the **author**; `/ingest` is the **translator**; `/implement` is the **builder**.
This skill owns the front of that pipeline: it decides *what* to build and *in what order*,
grounded in how the existing codebase actually works. The deliverable is design docs, never code.

The output is the contract. `/ingest` will classify these docs (overview, component-spec,
prompt-spec, api-contract, evaluation, implementation-plan) and decompose the
**implementation-plan**'s `## Phase N` headings into task files. So the docs must be written to
*that* shape — see step 4.

## Operating rules

- **Plan-first, approval-gated.** Investigate and design, then present the plan on screen and
  **wait for explicit approval** before writing any files. No design docs hit disk until the
  user says go.
- **Design, don't implement.** `/feature` writes Markdown design docs only. It does not modify
  application code, add dependencies, create branches, or open PRs.
- **Read the real codebase.** This is a feature for an *existing* project. Ground every decision
  in what's already there — conventions, frameworks, module boundaries, test setup, naming. A
  plan that ignores the host codebase is a bad plan.
- **`/ingest`-compatible by construction.** The docs you write must match what `/ingest` expects
  (numbered `NN-*.md`, classifiable kinds, an implementation-plan with `## Phase N` headings).
  Verify against step 4 before finishing.
- **Rigor over volume.** Verbatim schemas/contracts, explicit non-goals, named risks, and
  testable acceptance criteria beat long prose. Surface open questions; don't paper over them.

## Step 1 — Understand the feature *and* the project

You need two mental models: the feature being requested, and the codebase it lands in.

**The ask.** Start from `$ARGUMENTS` (a one-line feature description) or the user's message. If
it's empty or vague, that's fine — you'll clarify in step 2. Capture the user's words verbatim as
the seed; don't reinterpret yet.

**The project.** Build just enough context to design coherently (lighter than `/understand`, but
the same instinct). In parallel where possible:

- Read `README*`, `CLAUDE.md`/`AGENTS.md`, and the build/manifest file(s) — language, runtime,
  frameworks, scripts, test runner.
- Map the modules/dirs the feature will touch. Identify the **integration points**: which
  existing files, APIs, schemas, or UI surfaces this feature extends or hooks into.
- Note the project's conventions (how new modules/routes/tests are typically added) so the plan
  proposes work that looks native to this repo.
- `git log --oneline -15` for trajectory; `git status -sb` for in-flight work that might collide.

Use sub-agents (e.g. `Explore`) to fan out so raw file output stays out of the main thread — you
want conclusions: *where does this feature plug in, and what constraints does the codebase impose?*

## Step 2 — Clarify scope and acceptance

A spec is only as good as its boundaries. Before designing, resolve the load-bearing unknowns —
prefer one focused `AskUserQuestion` round (2–4 questions) over a long interview. Target:

- **Scope & non-goals** — what's explicitly in, what's explicitly out of *this* feature.
- **Acceptance criteria** — what observable behavior proves it's done? (drives the evaluation doc)
- **Constraints** — performance, security/authz, data model, backward-compat, platform, deadlines.
- **Integration choices** — when the codebase offers more than one sane way to plug in, ask which.

Don't ask what you can determine from the code or sensible defaults. If something stays genuinely
open after asking, record it as an **Open question** in the docs rather than guessing silently.

## Step 3 — Present the plan, get approval (the gate)

Before writing anything, show the user a concise plan on screen:

- **One-paragraph summary** of the feature and how it fits the existing system.
- **Proposed doc set** — the list of `NN-*.md` files you'll write and each one's kind.
- **Phase breakdown** — the ordered `## Phase N` list (the future task DAG), each phase one line.
- **Key design decisions** — the choices you're making and why, including integration points.
- **Risks / open questions** — what's uncertain or deferred.

Then **stop and ask for approval.** Incorporate edits and re-present if the user wants changes.
Only proceed to step 4 once they approve. (If running in an environment with a plan-mode/approval
affordance, use it; otherwise ask plainly: "Approve this plan and I'll write the design docs?")

## Step 4 — Write the `/ingest`-compatible design docs

On approval, write numbered `NN-*.md` files **flat into `docs/design/`** — that's the first
location `/ingest`'s bare auto-discovery scans, so a no-arg `/ingest` picks them up with no path
needed. Create `docs/design/` if it doesn't exist.

**Avoid collisions with existing docs.** `docs/design/` is shared and `/ingest` auto-discovers
*every* `NN-*.md` in it, so before writing, check what's already there:

- If it's empty (or only your own prior run for this feature), write the standard `01..0N`
  sequence below.
- If it already holds unrelated `NN-*.md` from another feature, **don't clobber the numbering or
  silently co-mingle.** Tell the user and offer: prefix this feature's files with its slug
  (`<slug>-01-overview.md`, … — still flat, still auto-discovered) so both sets coexist, or write
  to a `docs/design/<feature-slug>/` subfolder ingested with an explicit path. Default to the
  slug-prefix option since it keeps bare `/ingest` working.

**Required docs**, numbered in order. Use the `Kind:` line `/ingest` recognizes:

1. `01-overview.md` — **Kind: overview**. Goals, non-goals, the component map for the feature, and
   an explicit **Integration with existing code** section (which modules/APIs it extends, lifted
   from step 1). This is the system-level picture.
2. `0N-<component>-spec.md` — **Kind: component-spec**, one per non-trivial subsystem the feature
   introduces or substantially changes. Quote any data shapes/interfaces verbatim.
3. *(as needed)* `0N-api-contract.md` — **Kind: api-contract** for new/changed HTTP/CLI/RPC
   surfaces; `0N-prompt-spec.md` — **Kind: prompt-spec** for any LLM prompts/schemas. Copy
   schemas, signatures, and prompt text **verbatim** — never paraphrase load-bearing detail.
4. `0N-evaluation.md` — **Kind: evaluation**. The acceptance criteria from step 2 as concrete,
   verifiable checks (what command/observation proves each works). This is the test plan.
5. `0N-implementation-plan.md` — **Kind: implementation-plan**, written LAST and **highest-numbered**.
   This is the doc `/ingest` decomposes into tasks, so it is the most format-sensitive:

   ````markdown
   # <Feature> — Implementation Plan

   **Kind:** implementation-plan

   Ordered, phase-driven build-out. Each phase is ~1 PR of work and becomes one `tasks/NN-*.md`.

   ## Phase 1 — <name>
   **Goal:** <one sentence: what is true when this phase is done?>
   **Depends on:** none
   **Deliverables:**
   - <concrete deliverable>
   **Done when:** <verifiable check>

   ## Phase 2 — <name>
   **Goal:** …
   **Depends on:** Phase 1
   …
   ````

   **Phase rules:** every phase needs `## Phase N — <name>` exactly (that heading is what `/ingest`
   keys on), a one-sentence Goal, explicit Depends-on, concrete Deliverables, and a verifiable
   Done-when. Size each at ≈1 PR; if a phase exceeds ~1 week, split it (`## Phase 4a`, `## Phase 4b`).
   Order phases by dependency so the resulting task DAG is buildable top-to-bottom.

Also write a `docs/design/README.md` index (create it, or append a section for this feature if it
already exists) — a small table: `#`, doc, kind, one-line purpose — so the folder is
self-describing.

**Doc-writing rules** (same discipline `/ingest` enforces downstream):

- Quote, don't paraphrase, anything load-bearing — schemas, API shapes, prompts, acceptance checks.
- State non-goals explicitly in `01-overview.md` and per-phase anti-scope where it matters.
- Don't invent project facts. If you assumed something about the codebase, mark it as an
  assumption/open question rather than asserting it.

## Step 5 — Final report

Print a short summary:

- Feature: <one line> — written to `docs/design/`
- Docs: list each `NN-*.md` with its kind; note the phase count in the implementation plan.
- Open questions / risks worth the user's attention before building.
- **Next step:** `Run /ingest` (no path needed — it auto-discovers `docs/design/`) to generate
  `specs/` + `tasks/`, then `/implement` to build them. (If you used the slug-prefix or subfolder
  option to avoid a collision, give the exact `/ingest <path>` instead.)

Do **not** run `/ingest` or start implementing yourself — `/feature`'s deliverable is the design
docs and the plan behind them, not the specs, tasks, or code.

## Principles

- **The docs are the contract.** A fresh session (and `/ingest`) should understand the whole
  feature from this folder alone, with no access to the conversation that produced it.
- **Designed for the next stage.** Phases are written to `/ingest`'s shape on purpose — this skill
  exists to make the hand-off to `/ingest` → `/implement` clean and lossless.
- **Grounded, not generic.** Every plan is specific to *this* codebase's conventions and seams.
- **Approval is a hard gate.** Investigate and propose freely; write to disk only after sign-off.
