---
name: ingest
description: Ingest design documents (markdown, often numbered like 01-overview.md, sometimes inside a zip) and produce structured `specs/` and `tasks/` folders that Claude Code can implement against. Use when the user runs `/ingest`, asks to "build specs and tasks from these docs", or uploads design docs and wants them turned into actionable work files. Accepts a path argument, file attachments from the GUI (uploads), or auto-discovers docs in the repo.
---

# /ingest — design docs → specs + tasks

Turns one or more design markdown files into two deliverables in the current working directory:

- `specs/` — per-doc specifications, faithful to the source, indexed
- `tasks/` — phase- or component-sized implementation task files with checkboxes Claude Code can tick off

The output is the contract: a future Claude Code session should be able to start work by reading a single `tasks/NN-*.md` file without re-reading the original design docs.

## 1. Resolve the input

Find the source design docs in this priority order. **Stop at the first source that yields at least one `.md` file.**

1. **Explicit argument** — if `$ARGUMENTS` is non-empty, treat it as one of:
   - a directory: use every `*.md` inside (non-recursive unless the user says otherwise)
   - a single `.md` file: use just that file
   - a `.zip` file: unzip to a temp directory, then use every `*.md` inside
2. **Recently attached files** — scan the most recent user messages (this turn and the previous few) for paths under `/root/.claude/uploads/`, `/tmp/`, `/var/folders/.../`, or anything that looks like a fresh upload. If found, use those (unzipping zips first).
3. **Repo defaults** — look in this order for a folder containing `NN-*.md` files (numeric prefix, e.g. `01-overview.md`):
   - `./docs/design/`
   - `./design/`
   - `./docs/`
   - `./` (repo root)

If two sources both look plausible, ask the user which to use rather than guessing. If nothing resolves, ask the user to point you at the docs.

## 2. Read and classify each doc

Read every input `.md` file. For each, classify it as one of:

- `overview` / `architecture` — system-level design, goals, non-goals, component map
- `component-spec` — a single subsystem in detail (extractor, describer, etc.)
- `prompt-spec` — LLM prompts, schemas, and contracts
- `api-contract` — REST/HTTP/CLI surface definitions
- `evaluation` — test plans, scoring, success criteria
- `ops-runbook` — operations, deploy, observability
- `implementation-plan` — phase- or milestone-driven ordered work

Note the source filename and any phase/section structure (look for `## Phase N` or `## N.` style headings).

## 3. Generate `specs/`

Create `specs/` in the current working directory. If it already exists and is non-empty, ask before overwriting.

For each design doc, write `specs/<NN>-<slug>.md` (preserve the source's numeric prefix when present):

```markdown
# <Doc title>

**Source:** <relative path to original design doc>
**Kind:** <classification from step 2>
**Status:** Derived spec

## Summary
<2–4 sentences distilling the doc's purpose. No new claims.>

## Key requirements / contracts
<Bulleted requirements lifted from the doc. Be faithful — do not invent.>

## Schemas / interfaces
<Quote schemas, JSON shapes, API signatures, prompt text VERBATIM from the source. Do not paraphrase technical detail.>

## Open questions
<Anything marked TBD / TODO / "decide later" in the source.>

## Out of scope
<Explicit non-goals if present.>

## See also
- Original: <relative path>
- Related specs: <links to sibling specs/ files where relevant>
```

**Rules:**
- Do **not** lossily summarize technical detail (schemas, prompt text, API shapes, code blocks). Copy verbatim.
- Do **not** invent requirements not in the source.
- Do **not** resolve contradictions silently. If two design docs disagree, write `specs/00-conflicts.md` listing each conflict with quotes from both sources.

Write a `specs/README.md` index:

```markdown
# Specs

Derived from design docs on <YYYY-MM-DD> by `/ingest`.

| # | Spec | Kind | Source |
|---|---|---|---|
| 01 | … | overview | `…01-overview.md` |
| … |
```

## 4. Generate `tasks/`

The `tasks/` folder is the actionable work queue. Each task should be sized so a single Claude Code session can pick it up and finish it (roughly 1 PR worth of work).

**Decide the decomposition source:**

- If there is an `implementation-plan` doc with phases — drive tasks from its phases (one task per phase, in order).
- Else if there's an `overview` doc with a clear component list — one task per component, sequenced by dependencies.
- Else — ask the user how to decompose before writing any task files.

For each phase or component, write `tasks/<NN>-<slug>.md`:

```markdown
# Task <NN>: <Name>

**Goal:** <one-sentence outcome — what is true when this task is done?>
**Depends on:** <prior task numbers, or "none">
**Relevant specs:** <links to specs/*.md>
**Source:** <link to the phase/section of the original design doc>
**Est. effort:** <copied from source if present>

## Deliverables
- [ ] <concrete deliverable 1, lifted from source>
- [ ] <concrete deliverable 2>
- …

## Definition of done
- [ ] <verifiable check — what command/observation proves it works?>
- …

## Anti-deliverables (do NOT build in this task)
- <things explicitly out of scope for this phase, from source>

## Risks / unknowns
- <risks from source, if any>

## Notes for Claude Code
- Start by reading the linked `specs/` files and, if needed, the original source doc.
- Tick off boxes in this file as you complete them.
- If a deliverable is blocked, append `> blocked: <reason>` under it rather than removing it.
- Commit incrementally; one logical change per commit.
```

**Sizing rule:** If a source phase is estimated at more than ~1 week of work, split it into sub-tasks named `tasks/04a-…md`, `tasks/04b-…md`, etc. Keep the parent numeric prefix.

Write a `tasks/README.md` index:

```markdown
# Implementation Tasks

Generated by `/ingest` on <YYYY-MM-DD>.

Work top to bottom. Each task links its prerequisite specs and any tasks it depends on.

| # | Task | Status | Depends on |
|---|---|---|---|
| 01 | … | not started | – |
| 02 | … | not started | 01 |
| … |

## How to start a task

Open the relevant `tasks/NN-…md` and tell Claude Code:
> "Work on task NN. Read the file, do the deliverables, tick the boxes as you go."
```

## 5. Final report

Print a short summary to the user:

- Source: <what was ingested, from where>
- Wrote: N specs (`specs/`) and M tasks (`tasks/`)
- Any conflicts or open questions surfaced (point at `specs/00-conflicts.md` if it exists)
- Suggested next step: usually `open tasks/01-….md and start there`

Do **not** start implementing tasks unless the user asks. The deliverable of `/ingest` is the spec + task scaffolding, not the implementation.

## Principles

- **Faithful, not creative.** The skill is a translator, not a designer. If the source is silent on something, the spec is silent too.
- **Quote, don't paraphrase, for anything load-bearing** — schemas, prompts, contracts, success criteria.
- **Single-task autonomy.** A task file should be enough on its own (plus its linked specs) for a fresh Claude Code session to make progress without the original docs.
- **Surface ambiguity.** Conflicts, TBDs, and "decide later" notes belong in the output, not silently resolved.
