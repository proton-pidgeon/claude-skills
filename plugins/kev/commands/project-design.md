---
allowed-tools: Bash(gh:*), Bash(git:*), WebSearch, WebFetch, Read, Write, Edit, Glob, Grep
description: Run the full design-doc-first pipeline — idea → elicited decisions → numbered doc set → security model → HANDOVER.md in a new private repo
argument-hint: "<one-paragraph project goal>  |  continue <repo>  |  security <repo>  |  handover <repo>  (empty = help)"
---

Trigger for the `project-design` skill — Kev's end-to-end project design pipeline. The skill
holds the full playbook and also fires on natural language ("let's spec out…", "design a new
project", "I want to build…"). Exemplar output: `proton-pidgeon/synopsis`.

**If `$ARGUMENTS` is empty**, show this help text (do not run anything):

```
/project-design — idea to implementation-ready repo

  /project-design <goal paragraph>     Run the whole pipeline from the top:
                                        landscape → user stories → elicited decisions
                                        → repo + numbered doc set → open questions
                                        → design language → CIA+AuthN → HANDOVER.md
  /project-design continue <repo>      Resume: read the repo's docs, find the next
                                        incomplete phase, pick up there
  /project-design security <repo>      Run just the CIA + AuthN elicitation and write
                                        the security doc for an existing design set
  /project-design handover <repo>      Write/refresh HANDOVER.md from the current docs

How it behaves: questions come in rounds of ≤3 multiple-choice options; every answer
lands in a decision log; volatile facts get web-verified before they're encoded;
open questions are resolved with honesty grades (confirmed / probable-unverified /
resolved-as-design). The deliverable is the repo, ending in a HANDOVER.md so that
"read HANDOVER.md and begin M0" is a sufficient Claude Code prompt.

Natural language works too:
  "let's design <thing>"        "work through user stories first"
  "we need the security model"  "write the handover file"
```

**If `$ARGUMENTS` is provided**, invoke the `project-design` skill. Parse the first token:

1. `continue <repo>` → read the repo's `README` + `docs/` (and `HANDOVER.md` if present),
   determine which pipeline phase is incomplete (missing doc, unresolved open-questions table,
   placeholder security doc, absent HANDOVER.md), state your finding, and resume from there —
   elicitation phases still elicit; never backfill decisions by assumption.
2. `security <repo>` → run Phase 6 only (CIA + AuthN rounds → decision log → security doc →
   propagate schema/roadmap consequences to the other docs).
3. `handover <repo>` → run Phase 7 only: write or refresh `HANDOVER.md` from the docs as they
   stand, flag any doc/decision gaps it exposes rather than papering over them.
4. Anything else → treat `$ARGUMENTS` as the goal paragraph and run the pipeline from Phase 0.

Operational notes: repos are created **private** under `proton-pidgeon` (personal account — no
org flag); in Claude Code use `gh repo create` / `git` for repo work; on web/mobile the GitHub
connector's create/push tools are the equivalents. Push docs in logical commits. Defer all
process detail to the skill — do not re-derive the pipeline here.
