---
name: notebooklm-push
description: Send a finished research report to Google NotebookLM and generate an Audio Overview (podcast), via the notebooklm-bridge service on the home Mac (fronted by Peggy). Use when the user runs `/notebooklm`, or asks to "send this to NotebookLM", "make a podcast of this report", "push this report to NotebookLM", "turn this into an Audio Overview", or "create a notebook from this report". Defaults to the most recent research report in the session; accepts a file path or pasted markdown as an argument. Handles credential preflight, async submit + poll, and honest failure surfaces (stale Google session, upstream changes).
---

# notebooklm-push — report → NotebookLM notebook + podcast

Take a finished research report (typically a `deep-research` output) and get it into Google
NotebookLM as a **fresh notebook with the report as a source and an Audio Overview (podcast)**
generated from it. Works from any Claude surface: `/notebooklm` in Claude Code, or natural
language on web/mobile.

```
report markdown ──▶ notebooklm-bridge (home Mac, behind Peggy) ──▶ NotebookLM
                     POST /reports → job id → poll → notebook URL + MP3
```

This skill is a **thin client** over the bridge. All the unstable, session-bound NotebookLM
machinery lives server-side on the Mac; this skill only makes authenticated HTTP calls, which
is why it works from a phone with no browser and no Google cookies on the client.

## Why a service (don't try to run notebooklm-py here)

`notebooklm-py` has no official Google API — it drives a logged-in browser session that must
live on a real host. Do **not** attempt to invoke it directly from a Claude sandbox, install
it, or handle Google cookies. The only correct path is calling the bridge. If the bridge is
unreachable, report that — don't fall back to anything local.

## Configuration — read it, never hardcode

Credentials live in **`~/.claude/.notebooklm`** (gitignored, created by the user once):

```
NOTEBOOKLM_BRIDGE_URL="https://<peggy-host>/notebooklm"   # no trailing slash
NOTEBOOKLM_BEARER_TOKEN="<token>"
```

Never print, echo, or commit the token. If the file is missing or either value is empty,
stop and tell the user to create it (show the two lines above), then halt — do not proceed.

## Resolve the report

In order:
1. Empty argument or `last` → the **most recent research report** in this session (latest
   deep-research artifact). If there is none, say so and stop.
2. A readable file path → that file's contents.
3. Otherwise → treat the argument as report markdown directly.

Derive the **notebook title** from the report's first `# H1` line (strip the `#`). If there is
no H1, use the first non-empty line, truncated to ~200 chars.

## Do the work — via the helper script

All HTTP is done by `scripts/notebooklm_push.sh` (curl-based: submit, then poll). Invoke it;
do not reimplement the calls inline.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/notebooklm_push.sh --file <path-to-report.md> --title "<title>"
# or, for pasted text, the command writes a temp file first and passes --file
# optional: --instructions "<audio style>"  (omit to use the bridge's house style)
```

The script:
1. Sources `~/.claude/.notebooklm`; fails clearly if creds are missing.
2. `POST {BRIDGE_URL}/reports` with the bearer token and `{title, markdown}` → expects `202`
   with a `job_id` and `poll_url`.
3. Polls `GET {BRIDGE_URL}/reports/{job_id}` every ~12s until the state is terminal.
4. On `DONE` → prints `notebook_url` and an `audio_url`.
5. On any `FAILED_*` → prints the stage and error message and exits non-zero.

Surface its output to the user plainly. On success, give the **clickable notebook URL** and
note the **podcast** is downloadable at the audio URL (same bearer).

## Interpreting failures (the bridge's stable vocabulary)

| State / kind | What to tell the user |
|--------------|-----------------------|
| `503` on submit / `FAILED_AUTH` / `auth_stale` | The NotebookLM Google session on the Mac has expired. They must run `notebooklm login` on the host; this can't be fixed remotely. |
| `FAILED_UPSTREAM` / `endpoint_changed` | NotebookLM changed internally; `notebooklm-py` likely needs an upgrade on the host. Point to the bridge's conformance check. |
| `FAILED_UPSTREAM` / `rate_limited` | Throttled. Wait a bit and resend. |
| `FAILED_UPSTREAM` / `generation_failed` | The Audio Overview was refused/aborted. Retry, optionally simpler instructions. |
| `FAILED_TIMEOUT` / `timeout` | A stage ran over budget (host asleep or upstream slow). Retry. |
| `FAILED_INTERNAL` / `internal` | Bridge-side bug (disk/DB). Check host logs. |

Don't retry automatically on `FAILED_AUTH` or `FAILED_INTERNAL` — those need a human.

## Preflight (quick, before submitting)

1. `test -f ~/.claude/.notebooklm` and both vars non-empty — else stop with setup instructions.
2. Optional health check: `GET {BRIDGE_URL}/healthz` (unauthenticated). If `status` is
   `degraded` with `auth.state: stale`, warn the user up front that a re-login is likely
   needed, but you may still submit (the bridge will `503` cleanly if so).

## Guardrails — refuse these

- Never run or install `notebooklm-py` locally, or handle Google cookies/session files.
- Never print or commit `NOTEBOOKLM_BEARER_TOKEN`.
- Never fall back to a non-bridge path if the bridge is down — report the outage instead.
- Don't claim success until the helper reports `DONE` with a real notebook URL and a
  non-trivial MP3 (the bridge verifies size; trust its terminal state, not a guess).

## Composition

Pairs with `deep-research`: research a topic → report artifact → `/notebooklm` (or "send it
to NotebookLM") → notebook + podcast. The two are independent; this skill only needs the
report markdown and the bridge.
