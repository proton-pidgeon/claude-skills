---
name: project-design
description: Run Kev's full design-doc-first project design pipeline — from a one-paragraph goal to an implementation-ready GitHub repo with a numbered doc set, elicited decision logs, user stories, security (CIA+AuthN) model, design language, and a HANDOVER.md for Claude Code. Use when the user runs `/project-design`, or says "design a new project", "let's spec out <thing>", "I want to build <thing>", "create the design docs", "run the design process", "work through user stories first", or asks to take an idea to a Claude Code handoff. The defining moves are multiple-choice elicitation in small rounds, decision logs everywhere, search-verified facts, and honest open-question resolution. Exemplar output: proton-pidgeon/synopsis.
---

# /project-design — from idea to implementation-ready repo

This is the playbook for taking a one-paragraph goal ("I want personal finance software that…")
all the way to a private GitHub repo containing a complete, decision-encoded design doc set and a
`HANDOVER.md` that lets Claude Code start with "read HANDOVER.md and begin M0." The reference
execution is `proton-pidgeon/synopsis` (2026-07-07) — read it when in doubt about depth or tone.

The pipeline is phased. Phases 1–2 and 6–7 are *elicitation* phases (the user decides); the rest
are *execution* phases (you research, write, push). Never skip an elicitation phase by assuming.

## Elicitation mechanics (used throughout)

- Ask in **small rounds of ≤3 multiple-choice questions**, 2–4 options each, highest-leverage
  decisions first. On surfaces with an options widget, use it; in Claude Code, present numbered
  options in text and wait. Free-text is fine when choices can't be enumerated (bank names).
- Before asking, check whether the answer is already in the conversation, memory, or house
  conventions — but **house conventions are defaults to confirm, not facts to assert.** The user
  deviates sometimes (e.g. Synopsis chose Anthropic-API-only over the local-first default).
- Every answer goes into a **decision log** (a table with date) in the relevant doc. A design doc
  containing vibes instead of decisions is not done.
- Between rounds, reflect back what the answers imply ("operator-only re-auth means…") —
  consequences surfaced early are cheap.

## Phase 0 — Intake & landscape

Restate the goal and constraints in your own words. **Web-search the volatile facts** before
proposing anything: provider availability, pricing, API status, library health — the landscape
shifts (GoCardless died for new signups mid-2025; assuming it would have sunk Synopsis's UK plan).
Propose a stack aligned with house conventions (Python 3.12/FastAPI/Huey/SQLite/uv on the Mac
Studio; SvelteKit; Peggy for exposure). Include one honest **build-vs-adopt** paragraph naming the
nearest existing tool and what building adds. Then ask whether to proceed to user stories.

## Phase 1 — User stories (elicit)

Personas before features. Identify the **least technical / least tolerant user** and make their
stories the acceptance contract (the "wife test"): if their zero-effort path fails, v1 isn't done.
Typical persona split: casual viewer / power investigator / operator. For each: numbered stories
(`V1`, `I3`, `O2`…) with P1/P2/P3 priorities, plus **anti-stories** (explicitly rejected
capabilities) and acceptance themes. Remember the chronically forgotten stories: data staleness
visibility, credential/consent renewal as a routine chore not an edge case, and empty-history /
backfill. Offer to pressure-test with the real second user before freezing.

## Phase 2 — Core decisions (elicit)

Run elicitation rounds over the axes the project actually has. The recurring set: primary surface
& first-screen contract; AI posture (where inference runs — privacy vs quality is the user's call);
data presentation (regions/currencies/tenants); scope of v1; history/backfill ambition; ops
ownership (who fixes what); alert delivery; soft vs hard enforcement of any policy feature. Close
with: **name** (offer 3 Greek/Latin candidates with layered meaning + "I'll pick") and **delivery**
(new repo + push to main is the default).

## Phase 3 — Repo + doc set (execute)

Create the private repo under `proton-pidgeon` (it's a personal account, not an org — create
without an org parameter). Push a numbered doc set; the canonical spine, adapted per project:

```
README (etymology, principles, stack, doc index)
00-overview        vision, scope, non-goals, elicitation decision log
01-user-stories    personas, stories, anti-stories, acceptance themes
02-architecture    components, processes, data flow, boundaries
03-data-model      schema; money/units discipline; immutability posture
04-integrations    adapter interface + one doc-section per provider, incl. the manual Plan B
05-sync-and-ops    schedules, staleness, alerting, failure philosophy
06..0N             domain docs (currency, AI layer, UI, import, budgets…)
11-security        placeholder until Phase 7 makes it real
12-roadmap         milestones with EXIT CRITERIA + an explicit open-questions table
13-design-language after Phase 6
```

Rules: every doc encodes decisions (cite the elicitation date); milestones are sequenced
lowest-risk-vertical-slice first and each has a testable exit criterion; the roadmap's
**open-questions table is a feature, not an embarrassment** — unresolved things are named, never
papered over. Push in 2–3 logical commits with clear messages.

## Phase 4 — Resolve open questions (execute, honestly)

For each open question: web-search/verify what can be verified; decide what is yours to decide
(record the decision + rationale); elicit what is the user's. Record resolutions in three honest
grades: **confirmed** (with evidence), **probable but unverified** (with the cheap manual check
that settles it — e.g. "30 seconds on the provider's institution search"), or **resolved as
design** (the system stops needing the answer, e.g. per-user preference instead of guessing).
Never upgrade probable to confirmed for tidiness.

## Phase 5 — Design language (elicit, if there's a UI)

Consult the frontend-design skill first. Ground directions in the subject's own world and the
user's taste (classical/etymological hooks land well), then offer **3–4 genuinely distinct
directions** with vivid one-line identities — include one restrained and one indulgent option, and
name the trade-offs ("most Kev, most wife-veto risk"). On selection, write the token doc: 4–6
named hex values where color carries meaning; type roles with a semantic split; spacing/structure
rules; **one signature element** the app is remembered by; a motion budget; a self-critique note
naming the generic-default risks and how the design avoids them.

## Phase 6 — Security model (elicit — never skip, never inherit)

Run explicit **CIA + AuthN** rounds even when house patterns "obviously" apply — Synopsis's auth
was nearly shipped as an unexamined inheritance and the user rightly called it a miss. Axes:
C — who sees what within the tenant; encryption at rest (and the key-management reality: a key
beside the data is theater); session policy (name the actual threat, e.g. stolen phone).
I — enforcement level (convention vs DB-enforced vs + audit log); deletion vs voiding.
A — process posture; degraded-access path when the fancy front door is down; RPO.
AuthN — primary IdP and its failure modes; MFA (and what's actually enforceable vs policy — you
cannot enforce consumer-IdP MFA from the RP side; app-level TOTP is the enforceable equivalent);
recovery/break-glass (make it **loud**: rate-limited, audited, push-alerted); machine identities
(if none, the routes must not exist). Write the doc with the decision log on top, honest threat
notes that say what each control does *not* cover, and enforcement over convention throughout.

## Phase 7 — HANDOVER.md (execute)

Write `HANDOVER.md` at repo root: project in one paragraph; current state + current milestone with
exit criteria; any pre-work manual tasks flagged at the top; the doc index with one-liners; the
environment facts Claude Code cannot infer from code; **numbered standing constraints** (the
invariants that must never be violated, read-only/units/boundaries first); a suggested first
session that builds the load-bearing guarantees before anything else; and the **maintenance
contract**: updated at every milestone boundary so "read HANDOVER.md and continue" is always a
sufficient first prompt. Update doc 12 to reference it. Tell the user their opening CC prompt.

## Principles

- **Decisions, not vibes.** If a doc could have been written without the user, an elicitation was
  skipped.
- **Verify before encoding.** Anything about the outside world (providers, coverage, pricing,
  library status) gets searched, and citations of status get dates.
- **Honesty grades survive contact with tidiness.** Unverified stays labelled unverified, with its
  fallback written down.
- **Assumptions are questions in disguise.** Especially auth, and especially house patterns.
- **Exit criteria everywhere.** A milestone without a testable exit is a mood.
- **The repo is the deliverable.** Conversation is scaffolding; if it isn't in the docs, it
  didn't happen.
