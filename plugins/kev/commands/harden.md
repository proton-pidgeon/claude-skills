---
allowed-tools: Bash(git:*), Bash(node:*), Bash(uv:*), Bash(npm:*), Bash(make:*), Bash(pytest:*), Bash(cargo:*), Read, Write, Edit, Glob, Grep
description: Systematically triage and fix the findings of a code review (Codex adversarial review, /code-review, or the /implement gate), then verify green and commit
argument-hint: "[path to review output | pasted findings]  (empty = review the current diff, then fix)"
---

Trigger for the `harden` skill — systematically action the findings of a code review. The skill
holds the full playbook (triage → fix → verify → commit) and also fires on natural language
("fix the review findings", "apply the codex review", "address the review comments", "action the
review").

**If `$ARGUMENTS` is empty**, do not assume there is nothing to do — resolve the findings source
per the skill's Phase 0: use the most recent Codex/`/code-review` output in this session, or, if
there is none, offer to generate one with `/codex:adversarial-review` (or `/code-review`) on the
current diff and then harden it. Only show this help if the user is clearly asking what `/harden`
does:

```
/harden — fix the outputs of a code review, systematically

  /harden                      Use the latest review in this session (or offer to
                               run one on the current diff), triage each finding,
                               fix the real ones, verify green, and commit.
  /harden <path-to-review>     Harden from a saved review-output file.
  /harden <pasted findings>    Harden from findings pasted inline.

How it behaves: every finding gets a verdict — fix / defer / reject — with a reason
(a review is evidence, not a work order; lighter models overstate severity). Real
correctness/security fixes ship with a regression test. Nothing merges until the
verify command is green AND the specific behavior is re-exercised. The commit records
the full triage. Pairs with the /implement review gate and /codex.

Natural language works too:
  "fix the codex review findings"     "action the review"
  "apply the review to this branch"   "harden this from the review"
```

**If `$ARGUMENTS` is provided**, treat it as the findings source (a file path, or findings text)
and invoke the `harden` skill from Phase 0. Defer all process detail to the skill — do not
re-derive the triage/fix/verify pipeline here.

Operational notes: local CLI/Desktop only (edits code, runs the project's tests, commits). The
Codex path needs a working model — a ChatGPT-account login cannot use `gpt-5.5-codex`/`spark`;
set `~/.codex/config.toml` `model` to a supported one (e.g. `gpt-5.4-mini`) first. On Kev's solo
daily-driver repos, commit straight to `main`.
